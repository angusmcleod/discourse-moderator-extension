# name: discourse-category-moderator-lite
# about: Allows moderators to be assigned to categories to triage moderation
# version: 0.1
# authors: Angus McLeod

register_asset 'stylesheets/category-moderator.scss'

after_initialize do
  User.register_custom_field_type('moderator_category_id', :integer)

  require_dependency 'category'
  Category.class_eval do
    after_save :update_category_moderators

    def category_moderators
      self.custom_fields['category_moderators']
    end

    def update_category_moderators
      category_moderators.split(',').each do |u|
        user = User.find_by(username: u)
        user.custom_fields['moderator_category_id'] = self.id
        user.save!
      end
    end
  end

  require_dependency 'current_user_serializer'
  CurrentUserSerializer.class_eval do
    attributes :moderator_category_id, :category_flagged_posts_count

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
  end

  add_to_serializer(:flagged_topic, :category_id) {object.category_id}

  require_dependency 'post_action'
  PostAction.class_eval do
    after_save :update_category_counters

    def update_category_counters
      if PostActionType.notify_flag_type_ids.include?(post_action_type_id)
        post = Post.find(post_id)
        PostAction.update_category_flagged_posts_count(post.topic.category_id)
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
end
