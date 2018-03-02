# name: discourse-moderator-extension
# about: Extends Discourse moderation functionality
# version: 0.2
# authors: Angus McLeod
# url: https://github.com/angusmcleod/discourse-moderator-extension

register_asset 'stylesheets/moderator-extension.scss'

after_initialize do
  load File.expand_path('../lib/user_edits.rb', __FILE__)
  load File.expand_path('../lib/category_edits.rb', __FILE__)
  load File.expand_path('../lib/flagged_edits.rb', __FILE__)
  load File.expand_path('../lib/queued_edits.rb', __FILE__)
  load File.expand_path('../lib/moderator_extension.rb', __FILE__)
end
