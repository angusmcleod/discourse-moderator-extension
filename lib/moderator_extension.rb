module ::ModeratorExtension
  class Engine < ::Rails::Engine
    engine_name 'moderator_extension'
    isolate_namespace ModeratorExtension
  end
end

module ModeratorExtension
  def self.types
    @types ||= Enum.new(:default, :filtered, :restricted)
  end

  def self.all
    Group[:moderators].users
  end

  def self.category_moderators
    all.select { |u| u.moderator_category_ids.present? }
  end

  def self.non_category_moderators
    all - category_moderators
  end
end
