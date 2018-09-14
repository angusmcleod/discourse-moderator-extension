import { default as computed, on } from 'ember-addons/ember-computed-decorators';
import Category from 'discourse/models/category';
import { popupAjaxError } from 'discourse/lib/ajax-error';
import { ajax } from 'discourse/lib/ajax';

export default Ember.Component.extend({
  showSave: false,

  @on('didInsertElement')
  setup() {
    const categoryIds = this.get('user.moderator_category_ids');
    if (categoryIds) {
      const categories = categoryIds.map((id) => Category.findById(id));
      this.set('categories', categories);
    }
  },

  @computed('categories', 'user.moderator_category_ids')
  showSave(categories, initialIds) {
    if (!categories) return false;
    const categoryIds = categories.map((c) => c.id);
    return !_.isEqual(initialIds, categoryIds);
  },

  actions: {
    saveCategories() {
      const userId = this.get('user.id');
      const categories = this.get('categories') || [];
      const categoryIds = categories.map((c) => c.id);

      ajax(`/admin/users/${userId}/moderator_categories`, {
        type: 'PUT',
        data: {
          category_ids: categoryIds
        }
      }).then((result) => {
        if (result.success) {
          this.set('user.moderator_category_ids', result.moderator_category_ids);
        } else {
          this.send('restoreCategories');
        }
      }).catch(popupAjaxError);
    },

    restoreCategories() {
      const initialCategories = this.get('user.moderator_category_ids');
      this.set('categories', initialCategories);
    }
  }
});
