export default {
  setupComponent() {
    Ember.run.scheduleOnce('afterRender', () => {
      const $container = $('.moderator-list-container');
      $container.insertAfter($container.parent());
    });
  }
};
