import { typeMap } from '../lib/category-moderator-utilities';
import { default as computed, on } from 'ember-addons/ember-computed-decorators';
import { popupAjaxError } from 'discourse/lib/ajax-error';
import { ajax } from 'discourse/lib/ajax';

export default Ember.Component.extend({
  @on('init')
  setup() {
    const savedType = this.get('user.moderator_type');
    if (savedType !== undefined) {
      this.set('type', savedType);
    }
  },

  @computed('type', 'user.moderator_type')
  showSave(type, savedType) {
    return type !== savedType;
  },

  @computed
  moderatorTypes() {
    return Object.keys(typeMap).map((type) => {
      return { id: Number(type), name: I18n.t(`${typeMap[type]}.label`) };
    });
  },

  actions: {
    saveType() {
      const userId = this.get('user.id');
      const type = this.get('type');

      ajax(`/admin/users/${userId}/moderator_type`, {
        type: 'PUT',
        data: { type }
      }).then((result) => {
        if (result.success) {
          this.set('user.moderator_type', Number(result.type));
        } else {
          this.send('restoreType');
        }
      }).catch(popupAjaxError);
    },

    restoreType() {
      const savedType = this.get('user.moderator_type');
      this.set('type', savedType);
    }
  }
});
