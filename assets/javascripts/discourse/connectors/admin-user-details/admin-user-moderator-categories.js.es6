export default {
  setupComponent(attrs, component) {
    const isAdmin = component.get('currentUser.admin');
    const user = attrs.model;

    if (!isAdmin) {
      if (user.moderator && user.category_moderator) {
        const categories = user.moderator_category_ids.map((id) => Discourse.Category.findById(id));
        component.set('categories', categories);
      }
    }
  }
};
