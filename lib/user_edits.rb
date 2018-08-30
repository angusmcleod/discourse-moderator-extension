Discourse::Application.routes.append do
  namespace :admin, constraints: StaffConstraint.new do
    resources :users, id: RouteFormat.username, except: [:show] do
      put "moderator_type", constraints: AdminConstraint.new
      put "moderator_categories", constraints: AdminConstraint.new
    end
  end
end

User.register_custom_field_type('moderator_type', :integer)
User.register_custom_field_type('moderator_category_id', :integer)

require_dependency 'user'
class ::User
  after_commit :update_moderation

  def moderator_type
    if self.custom_fields['moderator_type']
      self.custom_fields['moderator_type']
    elsif moderator
      1
    else
      nil
    end
  end

  def category_moderator
    if moderator_category_ids.any? && moderator_type
      moderator_type === ModeratorExtension.types[:filtered] ||
      moderator_type === ModeratorExtension.types[:restricted]
    else
      false
    end
  end

  def moderator_category_ids
    [*self.custom_fields['moderator_category_id']]
  end

  def update_moderation
    if previous_changes[:moderator]
      if !moderator
        if moderator_category_ids.any?
          moderator_category_ids.each do |category_id|
            Category.remove_from_moderators(category_id, self.username)
          end
          UserCustomField.where(user_id: self.id, name: 'moderator_category_id').delete_all
        end

        if moderator_type.present?
          UserCustomField.where(user_id: self.id, name: 'moderator_type').delete_all
        end
      end
    end
  end
end

require_dependency 'current_user_serializer'
class ::CurrentUserSerializer
  attributes :category_moderator,
             :moderator_category_ids,
             :flagged_posts_category_counts,
             :flagged_posts_category_counts_total,
             :post_queue_new_category_counts,
             :post_queue_new_category_counts_total

  def category_moderator
    object.category_moderator
  end

  def inlcude_category_moderator?
    object.moderator?
  end

  def moderator_category_ids
    object.moderator_category_ids
  end

  def include_moderator_category_ids?
    object.moderator? && object.category_moderator
  end

  def flagged_posts_category_counts
    PostAction.user_flagged_posts_category_counts(object)
  end

  def include_flagged_posts_category_counts?
    object.moderator? && object.category_moderator
  end

  def flagged_posts_category_counts_total
    flagged_posts_category_counts.map { |c| c[:count] }.sum
  end

  def include_flagged_posts_category_counts_total?
    include_flagged_posts_category_counts?
  end

  def post_queue_new_category_counts
    QueuedPost.user_category_new_counts(object)
  end

  def include_post_queue_new_category_counts?
    object.moderator? && object.category_moderator
  end

  def post_queue_new_category_counts_total
    post_queue_new_category_counts.map { |c| c[:count] }.sum
  end

  def include_post_queue_new_category_counts_total?
    include_post_queue_new_category_counts?
  end
end

module CategoryGuardianExtension
  def allowed_category_ids
    result = super
    if caller[0].include?('flagged_posts_report') && @user.category_moderator
      result = @allowed_category_ids = @allowed_category_ids.select do |category_id|
        @user.moderator_category_ids.include?(category_id)
      end
    end
    result
  end
end

require_dependency 'guardian'
class ::Guardian
  prepend CategoryGuardianExtension

  def can_update_moderation?(user)
    can_administer?(user) && user.moderator?
  end
end

require_dependency 'admin/users_controller'
class Admin::UsersController
  def moderator_categories
    fetch_user
    guardian.ensure_can_update_moderation!(@user)

    new_ids = params[:category_ids].present? ? params[:category_ids].map(&:to_i) : []
    old_ids = @user.moderator_category_ids
    remove_ids = old_ids - new_ids
    add_ids = new_ids - old_ids

    if remove_ids.any?
      remove_ids.each do |category_id|
        Category.remove_from_moderators(category_id, @user.username)
      end
    end

    if add_ids.any?
      add_ids.each do |category_id|
        Category.add_to_moderators(category_id, @user.username)
      end
    end

    @user.custom_fields['moderator_category_id'] = new_ids
    @user.save_custom_fields(true)

    updated_ids = @user.reload.moderator_category_ids

    render json: success_json.merge(moderator_category_ids: updated_ids)
  end

  def moderator_type
    fetch_user
    guardian.ensure_can_update_moderation!(@user)
    params.require(:type)

    type = params[:type]

    @user.custom_fields['moderator_type'] = type
    @user.save_custom_fields(true)

    render json: success_json.merge(type: type)
  end
end

require_dependency 'admin_user_list_serializer'
class AdminUserListSerializer
  attributes :moderator_type, :category_moderator, :moderator_category_ids

  def moderator_type
    object.moderator_type
  end

  def category_moderator
    object.category_moderator
  end

  def moderator_category_ids
    object.moderator_category_ids
  end
end
