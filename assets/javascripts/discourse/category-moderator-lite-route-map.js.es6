export default function() {
  this.route('queued-posts', { path: '/queued-posts' }, function() {
    this.route('list', { path: ':filter' }, function() {
      this.route('category', { path: ':category_id' });
    });
  });
}
