import Category from 'discourse/models/category';

export default Discourse.Route.extend({
  setupController(controller, model) {
    const moderatorCategoryId = this.get('currentUser.moderator_category_id');
    if (moderatorCategoryId) {
      controller.set('moderatorCategory', Category.findById(moderatorCategoryId));
    }
  }
})
