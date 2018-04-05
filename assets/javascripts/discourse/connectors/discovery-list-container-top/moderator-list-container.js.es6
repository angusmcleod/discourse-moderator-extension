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
    } else {
      component.set('showModeratorList', false);
    }

    // We have to go overboard and observe every routeName change here because of the categories route.
    const excludedRoutes = ['discovery.categories', 'discovery.loading'];
    const controller = getOwner(this).lookup('controller:discovery');

    controller.addObserver('application.currentRouteName', () => {
      const currentRoute = controller.get('application.currentRouteName');
      const category = controller.get('category');

      if (category && excludedRoutes.indexOf(currentRoute) === -1) {
        setShowModeratorList(category);
      } else {
        component.set('showModeratorList', false);
      }
    });
  }
};
