import { withPluginApi } from 'discourse/lib/plugin-api';
import { observes } from 'ember-addons/ember-computed-decorators';
import Category from 'discourse/models/category';
import SiteHeader from 'discourse/components/site-header';

export default {
  name: 'category-moderator-edits',
  after: 'subscribe-user-notifications',

  initialize(container) {
    const user = container.lookup('current-user:main');
    const bus = container.lookup('message-bus:main');

    withPluginApi('0.8.10', api => {
      api.modifyClass('route:queued-posts', {
        redirect() {
          const moderatorCategoryId = this.get('currentUser.moderator_category_id');
          let filter = moderatorCategoryId ? 'category' : 'all';
          this.replaceWith('/queued-posts/' + filter);
        },

        setupController(controller) {
          const moderatorCategoryId = this.get('currentUser.moderator_category_id');
          if (moderatorCategoryId) {
            controller.set('moderatorCategory', Category.findById(moderatorCategoryId));
          }
        }
      });
    });

    if (user && user.get('moderator_category_id')) {

      bus.unsubscribe('/flagged_counts');
      bus.subscribe('/category_flagged_counts', data => {
        user.set('category_flagged_posts_count', data.total);
      });

      bus.unsubscribe('/queue_counts');
      bus.subscribe('/category_queue_counts', data => {
        user.set('post_queue_new_category_count', data.total);
      });

      SiteHeader.reopen({
        buildArgs() {
          const flaggedPostsCount = this.get('currentUser.category_flagged_posts_count');
          const queuedPostsCount = this.get('currentUser.post_queue_new_category_count');
          return {
            flagCount: flaggedPostsCount + queuedPostsCount,
            topic: this._topic,
            canSignUp: this.get('canSignUp')
          };
        },

        @observes('currentUser.category_flagged_posts_count', 'currentUser.post_queue_new_category_count')
        refreshCategoryFlagCount() {
          this.queueRerender();
        }
      });

      withPluginApi('0.8.8', api => {
        api.reopenWidget('hamburger-menu', {
          adminLinks: function() {
            const { currentUser } = this;

            const links = [{ route: 'admin', className: 'admin-link', icon: 'wrench', label: 'admin_title' },
                           { href: '/admin/flags',
                             className: 'flagged-posts-link',
                             icon: 'flag',
                             label: 'flags_title',
                             badgeClass: 'flagged-posts',
                             badgeTitle: 'notifications.total_flagged',
                             badgeCount: 'category_flagged_posts_count' }];

            if (currentUser.show_queued_posts) {
              links.push({ href: '/queued-posts/category',
                           className: 'queued-posts-link',
                           label: 'queue.title',
                           badgeCount: 'post_queue_new_category_count',
                           badgeClass: 'queued-posts' });
            }

            if (currentUser.admin) {
              links.push({ href: '/admin/site_settings/category/required',
                           icon: 'gear',
                           label: 'admin.site_settings.title',
                           className: 'settings-link' });
            }

            return links.map(l => this.attach('link', l));
          }
        });
      });

      const AdminFlagsPostsActiveRoute = requirejs('admin/routes/admin-flags-posts-active').default;
      const AdminFlagsPostsOldRoute = requirejs('admin/routes/admin-flags-posts-old').default;
      const AdminFlagsTopicsIndexRoute = requirejs('admin/routes/admin-flags-topics-index').default;

      const categoryModFilter = function(categoryId, items) {
        return items.filter((item) => item.topic.category_id === categoryId);
      };

      AdminFlagsPostsActiveRoute.reopen({
        setupController(controller, model) {
          const categoryId = this.get('currentUser.moderator_category_id');
          controller.set('model', categoryModFilter(categoryId, model));
        }
      });

      AdminFlagsPostsOldRoute.reopen({
        setupController(controller, model) {
          const categoryId = this.get('currentUser.moderator_category_id');
          controller.set('model', categoryModFilter(categoryId, model));
        }
      });

      AdminFlagsTopicsIndexRoute.reopen({
        setupController(controller, model) {
          const categoryId = this.get('currentUser.moderator_category_id');
          controller.set('flaggedTopics', categoryModFilter(categoryId, model));
        }
      });
    }
  }
};
