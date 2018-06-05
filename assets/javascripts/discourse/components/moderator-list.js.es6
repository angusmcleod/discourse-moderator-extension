import { default as computed } from 'ember-addons/ember-computed-decorators';
import { userPath } from 'discourse/lib/url';

export default Ember.Component.extend({
  classNames: 'moderator-list',
  router: Ember.inject.service('-routing'),
  currentRoute: Ember.computed.alias('router.router.currentRouteName'),

  @computed('category.category_moderators')
  moderators(moderators) {
    if (!moderators) return [];
    return moderators.map((m) => {
      Ember.set(m, 'url', userPath(m.username));
      return m;
    });
  },

  @computed('category', 'listLoading', 'currentRoute')
  showList(category, listLoading, currentRoute) {
    return currentRoute.indexOf('categories') === -1;
           !listLoading &&
           category &&
           category.category_moderators &&
           (category.moderator_list ||
            Discourse.SiteSettings.moderator_extension_show_category_list);
  }
});
