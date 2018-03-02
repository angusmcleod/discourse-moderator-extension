class ::PostAction
  after_save :update_category_counters

  def update_category_counters
    if PostActionType.notify_flag_type_ids.include?(post_action_type_id)
      post = Post.with_deleted.find(post_id)
      category_id = post ? post.topic.category_id : nil
      PostAction.update_flagged_posts_category_counts(category_id)
    end
  end

  def self.update_flagged_posts_category_counts(category_id = nil)
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

    msg = {
      count: posts_flagged_count,
      category_id: category_id
    }
    user_ids = UserCustomField.where(name: 'moderator_category_id', value: category_id).pluck(:user_id)
    MessageBus.publish('/flagged_posts_category_counts', msg, user_ids: user_ids)
  end

  def self.user_flagged_posts_category_counts(user = nil)
    return nil if !user || !user.moderator || !user.category_moderator
    user.moderator_category_ids.map do |category_id|
      {
        category_id: category_id,
        count: flagged_posts_category_count(category_id)
      }
    end
  end

  def self.flagged_posts_category_count(category_id = nil)
    return nil if !category_id
    $redis.get("#{category_id}_posts_flagged_count").to_i
  end
end

class ::Post
  def update_flagged_posts_count
    PostAction.update_flagged_posts_count
    PostAction.update_flagged_posts_category_counts(topic.category_id)
  end
end

class ::Topic
  def update_flagged_posts_count
    PostAction.update_flagged_posts_count
    PostAction.update_flagged_posts_category_counts(category_id)
  end
end

require_dependency 'admin/flags_controller'
require_dependency 'flag_query'
module FlagQueryExtension
  def flagged_posts_report(current_user, opts = nil)
    opts[:current_user_id] = current_user.id
    super(current_user, opts)
  end

  def flagged_post_actions(opts = nil)
    post_actions = super(opts)

    if opts[:current_user_id]
      current_user = User.find(opts[:current_user_id])

      if current_user.category_moderator
        category_ids = current_user.moderator_category_ids
        post_actions = post_actions.where(topics: { category_id: category_ids })
      end
    end

    post_actions
  end
end

module FlagQuery
  class << self
    prepend FlagQueryExtension
  end
end

require_dependency 'jobs/scheduled/pending_flags_reminder'
class ::Jobs::PendingFlagsReminder
  def execute(args)
    if SiteSetting.notify_about_flags_after > 0
      flagged_posts_count = PostAction.flagged_posts_count
      return unless flagged_posts_count > 0

      sorted_flags = pending_flags.sort_by { |f| f[:action_id] }

      if sorted_flags.any?
        triage_reminders(sorted_flags)
      end

      true
    end
  end

  def triage_reminders(flagged)
    category_moderators = ModeratorExtension.category_moderators
    non_category_moderators = ModeratorExtension.non_category_moderators

    if category_moderators.any?
      category_moderators.each do |user|
        relevant = flagged.select { |f| user.moderator_category_ids.include?(f[:category_id]) }
        count = relevant.size
        targets = [user.username]
        last_action_id = relevant.last[:action_id].to_i

        if get_last_notified_id_user(user.id).to_i < last_action_id && count > 0
          send_reminder(targets, count)
          set_last_notified_id_user(user.id, last_action_id)
        end
      end
    end

    if non_category_moderators.any?
      count = flagged.size
      targets = non_category_moderators.map(&:username)

      if last_notified_id.to_i < flagged.last[:action_id].to_i && count > 0
        send_reminder(targets, count)
        self.last_notified_id = flagged.last[:action_id]
      end
    end
  end

  def send_reminder(targets, count)
    PostCreator.create(
      Discourse.system_user,
      target_usernames: targets,
      archetype: Archetype.private_message,
      subtype: TopicSubtype.system_message,
      title: I18n.t('flags_reminder.subject_template', count: count),
      raw: I18n.t('flags_reminder.flags_were_submitted', count: SiteSetting.notify_about_flags_after)
    )
  end

  def pending_flags
    FlagQuery.flagged_post_actions(filter: 'active')
      .where('post_actions.created_at < ?', SiteSetting.notify_about_flags_after.to_i.hours.ago)
      .pluck(:id, :'topics.category_id')
      .map { |item| { action_id: item[0], category_id: item[1] } }
  end

  def set_last_notified_id_user(user_id, action_id)
    $redis.set("last_notified_pending_flag_id_#{user_id}", action_id)
  end

  def get_last_notified_id_user(user_id)
    $redis.get("last_notified_pending_flag_id_#{user_id}")
  end
end
