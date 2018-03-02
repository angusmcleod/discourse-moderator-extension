Category.register_custom_field_type('moderator_list', :boolean)

require_dependency 'category'
class ::Category
  def has_category_moderators?
    category_moderators && category_moderators.length > 0
  end

  def category_moderators
    if self.custom_fields['category_moderators']
      self.custom_fields['category_moderators']
    else
      ''
    end
  end

  def moderator_list
    if self.custom_fields['moderator_list']
      self.custom_fields['moderator_list']
    else
      false
    end
  end

  def self.remove_from_moderators(category_id, username)
    category = Category.find(category_id)
    category.custom_fields['category_moderators'] = category.category_moderators
      .split(',')
      .reject { |u| u == username }
      .join(',')
    category.save_custom_fields(true)
  end

  def self.add_to_moderators(category_id, username)
    category = Category.find(category_id)
    current = category.category_moderators.split(',')
    unless current.include?(username)
      category.custom_fields['category_moderators'] = current.push(username).join(',')
      category.save_custom_fields(true)
    end
  end
end

require_dependency 'basic_category_serializer'
class BasicCategorySerializer
  attributes :category_moderators, :moderator_list

  def category_moderators
    object.category_moderators.split(',').map do |username|
      BasicUserSerializer.new(User.find_by(username: username), scope: scope, root: false)
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
