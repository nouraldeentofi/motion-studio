// Watermark box for the export and poster dialogs: shows the mark, and removes it only with the owner's password.
import { emit } from './store.js';
import { h, icon, toast } from './ui.js';
import { WM_TEXT, watermarkOn, unlockWatermark, lockWatermark } from '../engine/watermark.js';

export function watermarkControl(onChange) {
  const box = h('div', { class: 'wm-box' });
  const changed = () => { emit('render'); onChange && onChange(); build(); };

  function build() {
    box.innerHTML = '';
    if (!watermarkOn()) {
      const back = h('button', { class: 'btn small', type: 'button' }, 'رجّعها');
      back.addEventListener('click', () => { lockWatermark(); toast('رجعت العلامة المائية'); changed(); });
      box.append(h('div', { class: 'wm-head' }, icon('unlock'), h('div', {}, h('b', {}, 'بلا علامة مائية'), h('small', {}, 'انشالت بكلمة السر على هالمتصفح')), back));
      return;
    }
    const open = h('button', { class: 'btn small ghost', type: 'button' }, 'شيلها');
    box.append(h('div', { class: 'wm-head' }, icon('lock'), h('div', {}, h('b', { class: 'mono', dir: 'ltr' }, WM_TEXT), h('small', {}, 'علامة مائية على كل فيديو وصورة')), open));
    open.addEventListener('click', () => {
      open.remove();
      const input = h('input', { class: 'input', type: 'password', placeholder: 'كلمة السر', autocomplete: 'off', dir: 'ltr' });
      const ok = h('button', { class: 'btn primary small', type: 'button' }, 'تأكيد');
      const msg = h('small', { class: 'wm-msg' });
      const tryIt = async () => {
        if (!input.value.trim()) { input.focus(); return; }
        ok.disabled = input.disabled = true;
        msg.textContent = 'عم اتأكد…';
        msg.classList.remove('bad');
        const good = await unlockWatermark(input.value);
        if (good) { toast('انشالت العلامة المائية'); changed(); return; }
        // a short pause makes guessing slower
        await new Promise((r) => setTimeout(r, 900));
        ok.disabled = input.disabled = false;
        msg.textContent = 'كلمة السر غلط';
        msg.classList.add('bad');
        input.select();
      };
      ok.addEventListener('click', tryIt);
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter') tryIt(); });
      box.append(h('div', { class: 'wm-form' }, input, ok), msg);
      input.focus();
    });
  }
  build();
  return box;
}
