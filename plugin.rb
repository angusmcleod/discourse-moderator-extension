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
      self.custom_fields['category_moderators']
    end

    def update_category_moderators
      UserCustomField.where(name: 'moderator_category_id', value: self.id).destroy_all

      category_moderators.split(',').each do |u|
        user = User.find_by(username: u)
        user.custom_fields['moderator_category_id'] = self.id
        user.save_custom_fields(true)
      end
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
end
