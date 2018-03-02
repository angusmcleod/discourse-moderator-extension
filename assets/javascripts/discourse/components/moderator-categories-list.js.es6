import Category from 'discourse/models/category';
import { default as computed } from 'ember-addons/ember-computed-decorators';

export default Ember.Component.extend({
  classNames: 'moderator-categories-list',
  showList: Ember.computed.alias('currentUser.category_moderator'),

  @computed('currentUser.moderator_category_ids')
  categories(categoryIds) {
    if (!categoryIds || !categoryIds.length) return [];
    return categoryIds.map((id) => Category.findById(id));
  }
});
