export default {
  setupComponent(attrs, component) {
    const category = attrs.category;
    if (category) {
      const enabled = Discourse.SiteSettings.moderator_extension_show_category_list || category.moderator_list;
      const hasModerators = category.category_moderators;
      component.set('showModeratorList', enabled && hasModerators);
    }
  }
};
