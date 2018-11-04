import { withPluginApi } from 'discourse/lib/plugin-api';
import { observes } from 'ember-addons/ember-computed-decorators';
import SiteHeader from 'discourse/components/site-header';
import { updateCounts } from '../lib/category-moderator-utilities';

export default {
  name: 'category-moderator-edits',
  after: 'subscribe-user-notifications',

  initialize(container) {
    const user = container.lookup('current-user:main');
    const bus = container.lookup('message-bus:main');

    if (user && user.category_moderator) {
      bus.unsubscribe('/flagged_counts');
      bus.subscribe('/flagged_posts_category_counts', data => {
        updateCounts(user, 'flagged_posts', data);
      });

      bus.unsubscribe('/queue_counts');
      bus.subscribe('/new_queue_category_counts', data => {
        updateCounts(user, 'post_queue_new', data);
      });

      SiteHeader.reopen({
        buildArgs() {
          const flaggedCounts = user.get('flagged_posts_category_counts_total');
          const queuedCounts = user.get('post_queue_new_category_counts_total');
          return $.extend({}, this._super(), {
            flagCount: flaggedCounts + queuedCounts
          });
        },

        @observes('currentUser.flagged_posts_category_counts_total', 'currentUser.post_queue_new_category_counts_total')
        refreshCategoryFlagCount() {
          this.queueRerender();
        }
      });

      withPluginApi('0.8.8', api => {
        api.reopenWidget('hamburger-menu', {
          adminLinks: function() {
            const { currentUser } = this;

            const links = [
              { route: 'admin',
                className: 'admin-link',
                icon: 'wrench',
                label: 'admin_title' },
              { href: '/admin/flags',
                className: 'flagged-posts-link',
                icon: 'flag',
                label: 'flags_title',
                badgeClass: 'flagged-posts',
                badgeTitle: 'notifications.total_flagged',
                badgeCount: 'flagged_posts_category_counts_total' }
            ];

            if (currentUser.show_queued_posts) {
              links.push({
                href: '/queued-posts',
                className: 'queued-posts-link',
                label: 'queue.title',
                badgeCount: 'post_queue_new_category_counts_total',
                badgeClass: 'queued-posts'
              });
            }

            if (currentUser.admin) {
              links.push({
                href: '/admin/site_settings/category/required',
                icon: 'gear',
                label: 'admin.site_settings.title',
                className: 'settings-link'
              });
            }

            return links.map(l => this.attach('link', l));
          }
        });
      });
    }
  }
};
