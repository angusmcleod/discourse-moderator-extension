import { cookAsync } from 'discourse/lib/text';
import { typeMap } from '../lib/category-moderator-utilities';
import { on, observes } from 'ember-addons/ember-computed-decorators';

export default Ember.Component.extend({
  @on('init')
  @observes('type')
  setup() {
    const key = this.get('key');
    const type = this.get('type');
    const text = I18n.t(`${typeMap[type || 1]}.${key}`);

    if (key === 'description') {
      cookAsync(text).then((cooked) => {
        this.set('formattedText', cooked);
      });
    } else {
      this.set('formattedText', text);
    }
  }
});
