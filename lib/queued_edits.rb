module NewPostManagerExtension
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

require_dependency 'new_post_manager'
class ::NewPostManager
  prepend NewPostManagerExtension
end

module QueuedPostsControllerExtension
  def index
    user = current_user
    if user.category_moderator
      state = QueuedPost.states[(params[:state] || 'new').to_sym]

      @queued_posts = QueuedPost.visible
        .where(state: state)
        .includes(:topic, :user)
        .order(:created_at)

      @queued_posts = @queued_posts.select do |post|
        user.moderator_category_ids.include?(post.post_options['category'].to_i)
      end

      render_serialized(@queued_posts,
                        QueuedPostSerializer,
                        root: :queued_posts,
                        rest_serializer: true,
                        refresh_queued_posts: "/queued_posts?status=new")
    else
      super
    end
  end
end

require_dependency 'queued_posts_controller'
class QueuedPostsController
  prepend QueuedPostsControllerExtension
end

require_dependency 'queued_post'
class QueuedPost
  def self.category_new_count(category_id = nil)
    return nil if !category_id

    new_posts.visible.select do |p|
      p['post_options'] && p['post_options']['category'].to_i == category_id.to_i
    end.count
  end

  def self.user_category_new_counts(user)
    return nil if !user || !user.moderator || user.moderator_category_ids.empty?
    user.moderator_category_ids.map do |category_id|
      {
        category_id: category_id,
        count: category_new_count(category_id)
      }
    end
  end

  def self.broadcast_category_new!(category_id)
    queued_new_count = QueuedPost.category_new_count(category_id)
    msg = {
      category_id: category_id,
      count: queued_new_count
    }
    user_ids = UserCustomField.where(name: 'moderator_category_id', value: category_id).pluck(:user_id)
    MessageBus.publish('/category_new_queue_counts', msg, user_ids: user_ids)
  end
end

require_dependency 'jobs/scheduled/pending_queued_posts_reminder'
class ::Jobs::PendingQueuedPostReminder
  def execute(args)
    return true unless SiteSetting.notify_about_queued_posts_after > 0

    sorted_queued = should_notify.sort_by { |f| f[:post_id] }

    if sorted_queued.any?
      triage_reminders(sorted_queued)
    end

    true
  end

  def triage_reminders(queued)
    category_moderators = ModeratorExtension.category_moderators
    non_category_moderators = ModeratorExtension.non_category_moderators

    if category_moderators.any?
      category_moderators.each do |user|
        relevant = queued.select { |q| user.moderator_category_ids.include?(q[:category_id]) }

        if relevant.any?
          count = relevant.size
          targets = [user.username]
          last_post_id = relevant.last[:post_id].to_i

          if get_last_notified_id_user(user.id).to_i < last_post_id && count > 0
            send_reminder(targets, count)
            set_last_notified_id_user(user.id, last_post_id)
          end
        end
      end
    end

    if non_category_moderators.any?
      count = queued.size
      targets = non_category_moderators.map(&:username)

      if last_notified_id.to_i < queued.last[:post_id].to_i && count > 0
        send_reminder(targets, count)
        self.last_notified_id = queued.last[:post_id]
      end
    end
  end

  def send_reminder(targets, count)
    PostCreator.create(
      Discourse.system_user,
      target_usernames: targets,
      archetype: Archetype.private_message,
      subtype: TopicSubtype.system_message,
      title: I18n.t('system_messages.queued_posts_reminder.subject_template', count: count),
      raw: I18n.t('system_messages.queued_posts_reminder.text_body_template', base_url: Discourse.base_url)
    )
  end

  def should_notify
    QueuedPost.new_posts.visible
      .where('created_at < ?', SiteSetting.notify_about_queued_posts_after.hours.ago)
      .pluck(:id, :post_options)
      .map { |item| { post_id: item[0], category_id: item[1]['category'].to_i } }
  end

  def set_last_notified_id_user(user_id, post_id)
    $redis.set("last_notified_queued_post_id_#{user_id}", post_id)
  end

  def get_last_notified_id_user(user_id)
    $redis.get("last_notified_queued_post_id_#{user_id}")
  end
end
