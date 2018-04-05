import { getOwner } from 'discourse-common/lib/get-owner';

export default {
  setupComponent(attrs, component) {
    const setShowModeratorList = (category) => {
      const enabled = Discourse.SiteSettings.moderator_extension_show_category_list || category.moderator_list;
      const hasModerators = category.category_moderators;
      component.set('showModeratorList', enabled && hasModerators);
    }

    if (attrs.category) {
      setShowModeratorList(attrs.category);
    }

    const controller = getOwner(this).lookup('controller:discovery');
    controller.addObserver('category', () => {
      const category = controller.get('category');
      if (category) {
        setShowModeratorList(category);
      } else {
        component.set('showModeratorList', false);
      }
    });
  }
};
