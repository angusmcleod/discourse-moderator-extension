# name: discourse-category-moderator-lite
# about: Allows moderators to be assigned to categories to triage moderation
# version: 0.1
# authors: Angus McLeod

register_asset 'stylesheets/category-moderator.scss'

after_initialize do
  User.register_custom_field_type('moderator_category_id', :integer)

  require_dependency 'category'
  Category.class_eval do
    after_save :update_category_moderators, if: :category_moderators

    def has_category_moderators?
      category_moderators && category_moderators.length > 0
    end

    def category_moderators
      self.custom_fields['category_moderators'] || ''
    end

    def update_category_moderators
      UserCustomField.where(name: 'moderator_category_id', value: self.id).destroy_all

      category_moderators.split(',').each do |u|
        user = User.find_by(username: u)
        user.custom_fields['moderator_category_id'] = self.id
        user.save_custom_fields(true)
      end

      Group.update_site_moderators
    end
  end

  require_dependency 'current_user_serializer'
  CurrentUserSerializer.class_eval do
    attributes :moderator_category_id,
               :category_flagged_posts_count,
               :post_queue_new_category_count

    def include_moderator_category_id?
      object.moderator?
    end

    def moderator_category_id
      object.custom_fields['moderator_category_id']
    end

    def include_category_flagged_posts_count?
      object.moderator? && !!moderator_category_id
    end

    def category_flagged_posts_count
      PostAction.category_flagged_posts_count(moderator_category_id)
    end

    def include_post_queue_new_category_count?
      object.moderator? && !!moderator_category_id
    end

    def post_queue_new_category_count
      QueuedPost.new_category_count(moderator_category_id)
    end
  end

  add_to_serializer(:flagged_topic, :category_id) { object.category_id }

  require_dependency 'post_action'
  PostAction.class_eval do
    after_save :update_category_counters

    def update_category_counters
      if PostActionType.notify_flag_type_ids.include?(post_action_type_id)
        post = Post.with_deleted.find(post_id)
        category_id = post ? post.topic.category_id : nil
        PostAction.update_category_flagged_posts_count(category_id)
      end
    end

    def self.update_category_flagged_posts_count(category_id = nil)
      return if !category_id

      posts_flagged_count = PostAction.active
        .flags
        .joins(post: :topic)
        .where('posts.deleted_at' => nil)
        .where('topics.deleted_at' => nil)
        .where('posts.user_id > 0')
        .where('topics.category_id' => category_id)
        .count('DISTINCT posts.id')

      $redis.set("#{category_id}_posts_flagged_count", posts_flagged_count)

      category = Category.find(category_id)
      user_ids = User.where(username: category.custom_fields['category_moderators']).pluck(:id)
      MessageBus.publish('/category_flagged_counts', { total: posts_flagged_count }, user_ids: user_ids)
    end

    def self.category_flagged_posts_count(category_id = nil)
      return nil if !category_id
      $redis.get("#{category_id}_posts_flagged_count").to_i
    end
  end

  Post.class_eval do
    def update_flagged_posts_count
      PostAction.update_flagged_posts_count
      PostAction.update_category_flagged_posts_count(topic.category_id)
    end
  end

  Topic.class_eval do
    def update_flagged_posts_count
      PostAction.update_flagged_posts_count
      PostAction.update_category_flagged_posts_count(category_id)
    end
  end

  module CategoryModExtension
    def enqueue(queue, reason = nil)
      result = super(queue, reason)
      post = result.queued_post
      category_id = post['post_options']['category']

      if category_id.length > 0
        category = Category.find(category_id)

        if category && category.has_category_moderators?
          QueuedPost.broadcast_category_new!(category.id) if post && post.errors.empty?
        end
      end

      result
    end
  end

  class ::NewPostManager
    prepend CategoryModExtension
  end

  QueuedPost.class_eval do
    def self.new_category_count(category_id = nil)
      return nil if !category_id

      new_posts.visible.select do |p|
        p['post_options'] && p['post_options']['category'].to_i == category_id.to_i
      end.count
    end

    def self.broadcast_category_new!(category_id)
      msg = { total: QueuedPost.new_category_count(category_id) }
      MessageBus.publish('/category_queue_counts', msg, user_ids: User.staff.pluck(:id))
    end
  end

  Discourse::Application.routes.append do
    get 'queued-posts/:filter' => 'queued_posts#index'
  end

  if !Group.exists?(name: 'site_moderators')
    group = Group.new(name: 'site_moderators'.to_s, automatic: true)
    group.default_notification_level = 2
    group.id = 4
    group.save!
  end

  ::Jobs::PendingFlagsReminder.class_eval do
    def active_moderator_usernames
      User.where(moderator: true)
        .human_users
        .joins(:user_custom_fields)
        .where('moderator_category_id IS NULL')
        .order('last_seen_at DESC')
        .limit(3)
        .pluck(:username)
    end
  end

  ::Jobs::PendingQueuedPostReminder.class_eval do
    def execute(args)
      return true unless SiteSetting.notify_about_queued_posts_after > 0

      queued_post_ids = should_notify_ids

      if queued_post_ids.size > 0 && last_notified_id.to_i < queued_post_ids.max
        PostCreator.create(
          Discourse.system_user,
          target_group_names: Group[:site_moderators].name,
          archetype: Archetype.private_message,
          subtype: TopicSubtype.system_message,
          title: I18n.t('system_messages.queued_posts_reminder.subject_template', count: queued_post_ids.size),
          raw: I18n.t('system_messages.queued_posts_reminder.text_body_template', base_url: Discourse.base_url)
        )

        self.last_notified_id = queued_post_ids.max
      end

      true
    end
  end

  require_dependency 'group'
  class ::Group
    after_save do
      if is_moderators?
        Group.update_site_moderators
      end
    end

    def is_moderators?
      self.name == 'moderators'
    end

    def self.update_site_moderators
      moderators = Group[:moderators]
      site_moderators = Group[:site_moderators]
      site_moderators.group_users.delete_all

      moderators.group_users.each do |u|
        unless UserCustomField.exists?(user_id: u.user_id, name: 'moderator_category_id')
          site_moderators.group_users.create!(user_id: u.user_id)
        end
      end

      site_moderators.save!
    end
  end

  require_dependency 'User'
  class ::User
    after_commit :update_category_moderators

    def moderator_category_id
      self.custom_fields['moderator_category_id']
    end

    def update_category_moderators
      if previous_changes[:moderator]
        if moderator_category_id.to_i > 0 && !moderator
          category = Category.find(moderator_category_id)
          category.custom_fields['category_moderators'] = category.category_moderators
            .split(',')
            .reject { |u| u == self.username }
            .join(',')
          category.save_custom_fields(true)

          self.custom_fields['moderator_category_id'] = nil
          self.save_custom_fields(true)
        end
      end
    end
  end
end
