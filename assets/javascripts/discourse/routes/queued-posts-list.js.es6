import DiscourseRoute from 'discourse/routes/discourse';

export default DiscourseRoute.extend({
  model(params) {
    this.filter = params.filter;
    return this.store.find('queuedPost', {status: 'new'});
  },

  setupController(controller, model) {
    const moderatorCategoryId = this.get('currentUser.moderator_category_id');
    let posts = model;

    if (this.filter === 'category' && moderatorCategoryId) {
      posts = model.filter((p) => {
        return p.category && p.category.id === moderatorCategoryId;
      });
    }

    controller.set('model', posts);
    controller.set('query', this.filter);
  }
});
