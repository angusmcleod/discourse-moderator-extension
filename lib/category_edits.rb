Category.register_custom_field_type('moderator_list', :boolean)

require_dependency 'category'
class ::Category
  def has_category_moderators?
    category_moderators && category_moderators.length > 0
  end

  def category_moderators
    UserCustomField.where(name: 'moderator_category_id', value: self.id).map do |record|
      User.find_by(id: record.user_id)
    end
  end

  def moderator_list
    if self.custom_fields['moderator_list']
      self.custom_fields['moderator_list']
    else
      false
    end
  end
end

Site.preloaded_category_custom_fields << 'moderator_list' if Site.respond_to? :preloaded_category_custom_fields

require_dependency 'basic_category_serializer'
class BasicCategorySerializer
  attributes :category_moderators, :moderator_list

  def category_moderators
    object.category_moderators.map do |user|
      BasicUserSerializer.new(user, scope: scope, root: false)
    end
  end

  def include_category_moderators?
    object.has_category_moderators?
  end

  def moderator_list
    object.moderator_list
  end

  def include_moderator_list?
    object.has_category_moderators?
  end
end
