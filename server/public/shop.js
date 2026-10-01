// Meltiew website: pieces and orbs, the shop with try-on, daily quests, gamepasses,
// the legal pages and support. Loaded before app.js; uses its helpers at call time.

const PIECE_SVG = (s = 20) => `<svg class="cur piece" width="${s}" height="${s}" viewBox="0 0 24 24" aria-hidden="true"><path fill="#ffb86b" stroke="#c9772a" stroke-width="1.2" d="M4 7.5h4.2c-.6-2.9 1-4.5 2.8-4.5s3.4 1.6 2.8 4.5H18v4.2c2.9-.6 4.5 1 4.5 2.8s-1.6 3.4-4.5 2.8V21H13.8c.6-2.9-1-4.5-2.8-4.5S7.6 18.1 8.2 21H4v-4.2c2.9.6 4.5-1 4.5-2.8S6.9 10.6 4 11.2z"/></svg>`;
const ORB_SVG = (s = 20) => `<svg class="cur orb" width="${s}" height="${s}" viewBox="0 0 24 24" aria-hidden="true"><defs><radialGradient id="og" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#e6dcff"/><stop offset=".6" stop-color="#9d7bff"/><stop offset="1" stop-color="#6c4bd8"/></radialGradient></defs><circle cx="12" cy="12" r="10" fill="url(#og)"/><circle cx="12" cy="12" r="3.6" fill="#fff" opacity=".9"/></svg>`;
const priceHtml = (p, cur) => (!p ? '' : (cur || (p.pieces ? 'pieces' : 'orbs')) === 'pieces' ? `${PIECE_SVG(18)}<b>${p.pieces}</b>` : `${ORB_SVG(18)}<b>${p.orbs}</b>`);
// One buy button per currency the item is sold for: pieces always, orbs for some.
const buyButtons = (it) => ['pieces', 'orbs'].filter((c) => it.price?.[c])
  .map((c, i) => `<button class="btn small ${i ? 'ghost' : ''} buy-${c}" data-buy="${esc(it.id)}" data-cur="${c}">${i ? '' : t('buy') + ' '}${priceHtml(it.price, c)}</button>`).join('');
const piecesText = (w) => (w?.infinite ? '∞' : String(w?.pieces ?? 0));

const SHOP_T = {
  en: {
    shop: 'Shop', wallet: 'Pieces', quests: 'Quests', pieces: 'Pieces', orbs: 'Orbs',
    pieces_about: 'Pieces are bought and spent on items and gamepasses.',
    orbs_about: 'Orbs are free: you get some every day you visit and for daily quests.',
    buy_pieces: 'Buy pieces', buy_for: 'Buy for {0} ₽', pack_bonus: '+{0} bonus',
    pay_soon: 'Buying pieces opens very soon.', pay_opening: 'Opening the payment page...',
    pay_waiting: 'Waiting for the payment to go through...', pay_done: 'Done! +{0} pieces', pay_failed: "The payment didn't go through",
    pay_note: 'Payment through SBP or crypto (RollyPay). By paying you accept the {0} and the {1}.',
    history: 'History', no_history: 'Nothing yet', terms_acc: 'terms of service', privacy_acc: 'privacy policy',
    r_daily: 'Daily visit', r_quest: 'Quest', r_purchase: 'Bought pieces', r_buy_accessory: 'Accessory', r_buy_face: 'Face',
    r_gamepass: 'Gamepass', r_gamepass_sale: 'Gamepass sale', r_community_payout: 'From a community', r_admin: 'From the administration', r_refunded: 'Refund', r_chargeback: 'Payment cancelled',
    try_on: 'Try on', take_off: 'Take off', wear: 'Wear', owned: 'Yours', buy: 'Buy', bought: 'Bought!',
    accessories: 'Accessories', faces_tab: 'Faces', free: 'Free', your_look: 'Your look', save_look: 'Save look',
    look_saved: 'Look saved', only_owned: 'Buy the items you are trying on first',
    clothing_tab: 'Clothes', take_free: 'Take it', no_clothing_shop: 'No clothes yet. Anyone can make one in Studio.',
    only_owned_clothes: 'Clothes you only tried on were not saved',
    daily_bonus: '+{0} orbs for coming today!', daily_note: 'Every day you visit: +{0} orbs. Three new quests each day.',
    claim: 'Claim +{0}', claimed: 'Claimed', go: 'Go',
    q_playground10: 'Play on the Playground for 10 minutes', q_friend: 'Play in any place together with a friend',
    q_places3: 'Visit 3 different places', q_play30: 'Play for 30 minutes', q_like: 'Like a place', q_emotes5: 'Use 5 emotes in the game',
    passes: 'Gamepasses', no_passes: 'No gamepasses yet', pass_owned: 'Owned', buy_pass_q: 'Buy "{0}" for {1} pieces?',
    passes_manage: 'Gamepasses', pass_name: 'Name', pass_price: 'Price in pieces', pass_desc: 'What it gives (description)',
    pass_image: 'Picture (square)', pass_add: 'Add gamepass', pass_sales: '{0} sold', pass_delete: 'Delete',
    pass_hint: 'Players buy passes for pieces; you get 95% of the price. In scripts: MarketplaceService:UserOwnsGamePassAsync(player.UserId, id).',
    terms: 'Terms of service', privacy_policy: 'Privacy policy', support: 'Support',
    badges: 'Badges', no_badges: 'No badges yet', badge_add: 'Add a badge', badge_name: 'Badge name', badge_desc: 'What it is for',
    badge_hint: 'Up to 15 per place. Give them out from a server Script: BadgeService:AwardBadge(player.UserId, id).',
    badge_awarded: '{0} have it', badge_delete_q: 'Delete this badge? Players lose it from their profiles.', profile_tab: 'Profile', no_badges_user: 'No badges yet. Places give them out for doing things.',
    support_title: 'Support', support_text: 'Something broke, a payment went wrong or you want to report something? Write to us, we answer here.',
    subject: 'Subject', message: 'Message', contact: 'Contact for the answer (email or Telegram)', send_ticket: 'Send',
    ticket_sent: 'Sent! The answer will appear below.', my_tickets: 'Your requests', ticket_open: 'Waiting for an answer', ticket_closed: 'Answered',
    support_other: 'Other ways to reach us', operator: 'Operator',
    adm_economy: 'Money', adm_tickets: 'Support', adm_give: 'Give pieces or orbs', adm_give_user: 'Username', adm_amount: 'Amount (minus takes away)',
    adm_give_btn: 'Give', adm_pay_cfg: 'RollyPay', adm_api_key: 'API key', adm_secret: 'Signing secret', adm_test: 'Test mode',
    adm_site: 'Site address', adm_callback: 'Callback URL for the RollyPay terminal', adm_key_set: 'saved', adm_key_empty: 'not set',
    adm_legal: 'Legal details (shown on the Terms, Privacy and Support pages)', adm_operator: 'Operator (name or company)',
    adm_inn: 'INN (if any)', adm_email: 'Support email', adm_tg: 'Support Telegram (@username)', adm_payments: 'Payments',
    adm_total: '{0} paid, {1} ₽', adm_reply: 'Reply', adm_close: 'Reply and close', adm_no_tickets: 'No requests',
    adm_mail_hint: 'Requests from the site and letters to {0}.', adm_by_mail: 'email', adm_emailed: 'sent by email',
    adm_reply_mail: 'The answer goes by email to {0}.', adm_reply_site: 'No email: the answer shows on their Support page.',
    adm_reply_nowhere: 'No account and no email: they won\'t see the answer.', adm_send: 'Reply and close',
    adm_close_only: 'Close without answering', adm_reopen: 'Open again', adm_spam: 'Spam',
    adm_spam_q: 'Block {0} and delete this request? Letters from that address won\'t come in any more.',
    adm_delete_q: 'Delete this request and its files?', adm_sent_mail: 'Sent by email',
    adm_mail_failed: 'Saved, but the email didn\'t go out: {0}',
  },
  ru: {
    shop: 'Магазин', wallet: 'Кусочки', quests: 'Задания', pieces: 'Кусочки', orbs: 'Опыт',
    pieces_about: 'Кусочки покупаются и тратятся на вещи и геймпассы.',
    orbs_about: 'Опыт бесплатный: его дают каждый день за заход и за ежедневные задания.',
    buy_pieces: 'Купить кусочки', buy_for: 'Купить за {0} ₽', pack_bonus: '+{0} в подарок',
    pay_soon: 'Покупка кусочков откроется совсем скоро.', pay_opening: 'Открываем страницу оплаты...',
    pay_waiting: 'Ждём, пока пройдёт оплата...', pay_done: 'Готово! +{0} кусочков', pay_failed: 'Оплата не прошла',
    pay_note: 'Оплата через СБП или криптовалютой (RollyPay). Оплачивая, ты принимаешь {0} и {1}.',
    history: 'История', no_history: 'Пока пусто', terms_acc: 'пользовательское соглашение', privacy_acc: 'политику конфиденциальности',
    r_daily: 'Ежедневный заход', r_quest: 'Задание', r_purchase: 'Покупка кусочков', r_buy_accessory: 'Аксессуар', r_buy_face: 'Лицо',
    r_gamepass: 'Геймпасс', r_gamepass_sale: 'Продажа геймпасса', r_community_payout: 'От сообщества', r_admin: 'От администрации', r_refunded: 'Возврат', r_chargeback: 'Отмена платежа',
    try_on: 'Примерить', take_off: 'Снять', wear: 'Надеть', owned: 'Есть', buy: 'Купить', bought: 'Куплено!',
    accessories: 'Аксессуары', faces_tab: 'Лица', free: 'Бесплатно', your_look: 'Твой образ', save_look: 'Сохранить образ',
    look_saved: 'Образ сохранён', only_owned: 'Сначала купи вещи, которые примеряешь',
    clothing_tab: 'Одежда', take_free: 'Забрать', no_clothing_shop: 'Одежды пока нет. Сделать её может кто угодно в Студии.',
    only_owned_clothes: 'То, что только примерял, не сохранилось',
    daily_bonus: '+{0} опыта за сегодняшний заход!', daily_note: 'Каждый день за заход: +{0} опыта. Каждый день три новых задания.',
    claim: 'Забрать +{0}', claimed: 'Получено', go: 'Перейти',
    q_playground10: 'Поиграй на площадке 10 минут', q_friend: 'Поиграй в любом плейсе вместе с другом',
    q_places3: 'Зайди в 3 разных плейса', q_play30: 'Поиграй 30 минут', q_like: 'Лайкни плейс', q_emotes5: 'Используй 5 эмоций в игре',
    passes: 'Геймпассы', no_passes: 'Геймпассов пока нет', pass_owned: 'Есть', buy_pass_q: 'Купить «{0}» за {1} кусочков?',
    passes_manage: 'Геймпассы', pass_name: 'Название', pass_price: 'Цена в кусочках', pass_desc: 'Что даёт (описание)',
    pass_image: 'Картинка (квадратная)', pass_add: 'Добавить геймпасс', pass_sales: 'Продано: {0}', pass_delete: 'Удалить',
    pass_hint: 'Игроки покупают пассы за кусочки, тебе достаётся 95% цены. В скриптах: MarketplaceService:UserOwnsGamePassAsync(player.UserId, id).',
    terms: 'Пользовательское соглашение', privacy_policy: 'Политика конфиденциальности', support: 'Поддержка',
    badges: 'Значки', no_badges: 'Значков пока нет', badge_add: 'Добавить значок', badge_name: 'Название значка', badge_desc: 'За что даётся',
    badge_hint: 'До 15 на плейс. Выдаются из серверного скрипта: BadgeService:AwardBadge(player.UserId, id).',
    badge_awarded: 'есть у {0}', badge_delete_q: 'Удалить значок? У игроков он пропадёт из профиля.', profile_tab: 'Профиль', no_badges_user: 'Значков пока нет. Их выдают плейсы за достижения.',
    support_title: 'Поддержка', support_text: 'Что-то сломалось, не прошла оплата или хочешь пожаловаться? Напиши нам, ответ придёт сюда.',
    subject: 'Тема', message: 'Сообщение', contact: 'Контакт для ответа (почта или Telegram)', send_ticket: 'Отправить',
    ticket_sent: 'Отправлено! Ответ появится ниже.', my_tickets: 'Твои обращения', ticket_open: 'Ждёт ответа', ticket_closed: 'Отвечено',
    support_other: 'Другие способы связи', operator: 'Оператор',
    adm_economy: 'Деньги', adm_tickets: 'Поддержка', adm_give: 'Выдать кусочки или опыт', adm_give_user: 'Логин', adm_amount: 'Сколько (минус забирает)',
    adm_give_btn: 'Выдать', adm_pay_cfg: 'RollyPay', adm_api_key: 'API-ключ', adm_secret: 'Секрет подписи', adm_test: 'Тестовый режим',
    adm_site: 'Адрес сайта', adm_callback: 'Callback URL для кассы RollyPay', adm_key_set: 'сохранён', adm_key_empty: 'не задан',
    adm_legal: 'Реквизиты (видны на страницах соглашения, политики и поддержки)', adm_operator: 'Оператор (ФИО или организация)',
    adm_inn: 'ИНН (если есть)', adm_email: 'Почта поддержки', adm_tg: 'Telegram поддержки (@username)', adm_payments: 'Платежи',
    adm_total: 'Оплачено {0}, {1} ₽', adm_reply: 'Ответить', adm_close: 'Ответить и закрыть', adm_no_tickets: 'Обращений нет',
    adm_mail_hint: 'Обращения с сайта и письма на {0}.', adm_by_mail: 'почта', adm_emailed: 'ушло на почту',
    adm_reply_mail: 'Ответ уйдёт на почту {0}.', adm_reply_site: 'Почты нет: ответ появится у человека на странице поддержки.',
    adm_reply_nowhere: 'Ни аккаунта, ни почты: человек ответ не увидит.', adm_send: 'Ответить и закрыть',
    adm_close_only: 'Закрыть без ответа', adm_reopen: 'Открыть снова', adm_spam: 'Спам',
    adm_spam_q: 'Заблокировать {0} и удалить обращение? Письма с этого адреса больше не будут приходить.',
    adm_delete_q: 'Удалить обращение вместе с файлами?', adm_sent_mail: 'Отправлено на почту',
    adm_mail_failed: 'Сохранено, но письмо не ушло: {0}',
  },
};

async function refreshMe() {
  try {
    const r = await api('GET', '/api/me');
    state.me = r.user;
    if (r.daily_bonus) toast(t('daily_bonus', r.daily_bonus));
  } catch {}
}

// Balance chip in the header: tap to buy pieces.
function walletChip() {
  if (!state.me?.wallet) return '';
  const w = state.me.wallet;
  return `<a class="wallet-chip" href="/wallet" data-link title="${esc(t('wallet'))}">${PIECE_SVG(18)}<b>${piecesText(w)}</b>${ORB_SVG(18)}<b>${w.orbs}</b></a>`;
}

function balanceCards(w) {
  return `<div class="grid2 balances">
    <a class="card balance" href="/wallet" data-link>${PIECE_SVG(40)}<div><span class="muted">${t('pieces')}</span><b>${piecesText(w)}</b><small class="muted">${t('pieces_about')}</small></div></a>
    <a class="card balance" href="/quests" data-link>${ORB_SVG(40)}<div><span class="muted">${t('orbs')}</span><b>${w?.orbs ?? 0}</b><small class="muted">${t('orbs_about')}</small></div></a></div>`;
}

// A small 3D picture of one accessory, drawn once in the browser and kept.
const thumbCache = {};
let thumbGl = null;
let thumbQueue = Promise.resolve();
function accessoryThumb(id) {
  if (thumbCache[id]) return thumbCache[id];
  thumbCache[id] = (thumbQueue = thumbQueue.then(async () => {
    try {
      const { THREE } = await loadThree();
      const def = (await loadAccessories()).items?.find((i) => i.id === id);
      if (!def) return '';
      if (!thumbGl) {
        thumbGl = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
        thumbGl.setSize(160, 160);
        thumbGl.setPixelRatio(1);
        thumbGl.outputColorSpace = THREE.SRGBColorSpace;
      }
      const scene = new THREE.Scene();
      scene.add(new THREE.HemisphereLight(0xffffff, 0x5b4a80, 2.4));
      const key = new THREE.DirectionalLight(0xffffff, 2.2);
      key.position.set(2, 3, 4);
      scene.add(key);
      const rim = new THREE.DirectionalLight(0xe9e2ff, 2.5);
      rim.position.set(-2, 2, -4);
      scene.add(rim);
      const obj = buildAccessory(THREE, def);
      scene.add(obj);
      obj.updateMatrixWorld(true);
      const box = new THREE.Box3().setFromObject(obj);
      const center = box.getCenter(new THREE.Vector3());
      const radius = Math.max(box.getSize(new THREE.Vector3()).length() / 2, 0.1);
      const dir = new THREE.Vector3(0.55, 0.35, def.slot === 'back' ? -1 : 1).normalize();
      const camera = new THREE.PerspectiveCamera(30, 1, 0.01, 100);
      camera.position.copy(center).addScaledVector(dir, (radius / Math.tan((15 * Math.PI) / 180)) * 1.05);
      camera.lookAt(center);
      thumbGl.render(scene, camera);
      return thumbGl.domElement.toDataURL('image/png');
    } catch (e) {
      console.warn('thumbnail failed', e);
      return '';
    }
  }));
  return thumbCache[id];
}

const SHOP_ROUTES = {
  async '/wallet'(root) {
    if (!state.me) { sessionStorage.setItem('after_login', '/wallet'); return go('/login'); }
    await refreshMe();
    const [{ packs, payments }, { history }] = await Promise.all([api('GET', '/api/pay/packs'), api('GET', '/api/me/wallet')]);
    const base = packs[0].rub / packs[0].pieces;
    root.innerHTML = `<h1>${t('wallet')}</h1>${balanceCards(state.me.wallet)}
      <h2>${t('buy_pieces')}</h2>
      ${payments ? '' : `<div class="empty">${t('pay_soon')}</div>`}
      <div class="packs">${packs.map((p) => {
        const bonus = Math.round(p.pieces - p.rub / base);
        return `<div class="card pack">${PIECE_SVG(46)}<b class="big">${p.pieces}</b>
          ${bonus > 2 ? `<span class="pill mintpill">${esc(t('pack_bonus', bonus))}</span>` : '<span class="pill" style="visibility:hidden">.</span>'}
          <button class="btn" data-pack="${p.id}" ${payments ? '' : 'disabled'}>${esc(t('buy_for', p.rub))}</button></div>`;
      }).join('')}</div>
      <p class="muted small-note">${t('pay_note', `<a href="/terms" data-link>${t('terms_acc')}</a>`, `<a href="/privacy" data-link>${t('privacy_acc')}</a>`)}</p>
      <h2>${t('history')}</h2>
      <div class="card stack">${history.length ? history.map((h) => `<div class="row"><span class="grow">${esc(t('r_' + h.reason) === 'r_' + h.reason ? h.reason : t('r_' + h.reason))}${h.ref && h.reason !== 'purchase' && h.reason !== 'daily' ? ` · <span class="muted">${esc(h.ref)}</span>` : ''}</span>
        <span class="muted">${esc(ago(h.created_at))}</span><b class="${h.delta > 0 ? 'plus' : 'minus'}">${h.delta > 0 ? '+' : ''}${h.delta}</b>${h.currency === 'pieces' ? PIECE_SVG(16) : ORB_SVG(16)}</div>`).join('') : `<span class="muted">${t('no_history')}</span>`}</div>`;
    root.querySelectorAll('[data-pack]').forEach((b) => b.addEventListener('click', async () => {
      b.disabled = true;
      toast(t('pay_opening'));
      try {
        const r = await api('POST', '/api/pay', { pack: b.dataset.pack });
        sessionStorage.setItem('pending_pay', r.id);
        location.href = r.pay_url;
      } catch (e) { toast(e.message, 'error'); b.disabled = false; }
    }));
    // Back from the payment page: wait for the bank's confirmation.
    const params = new URLSearchParams(location.search);
    const payId = params.get('paid') || params.get('failed') || sessionStorage.getItem('pending_pay');
    if (payId) {
      sessionStorage.removeItem('pending_pay');
      history.replaceState({}, '', '/wallet');
      const note = modal(`<h3>${t('pay_waiting')}</h3><div class="loader"><i></i></div>`);
      for (let i = 0; i < 40 && note.isConnected; i++) {
        let p;
        try { p = await api('GET', '/api/pay/' + encodeURIComponent(payId)); } catch { break; }
        if (p.status === 'paid') { note.remove(); toast(t('pay_done', p.pieces)); return render(); }
        if (['canceled', 'expired', 'failed'].includes(p.status)) { note.remove(); toast(t('pay_failed'), 'error'); return; }
        await new Promise((res) => setTimeout(res, 3000));
      }
      note.remove();
    }
  },

  async '/quests'(root) {
    if (!state.me) { sessionStorage.setItem('after_login', '/quests'); return go('/login'); }
    await refreshMe();
    const draw = async () => {
      const r = await api('GET', '/api/quests');
      root.innerHTML = `<h1>${t('quests')}</h1>${balanceCards(r.wallet)}
        <p class="muted">${esc(t('daily_note', r.daily_orbs))}</p>
        <div class="stack">${r.quests.map((q) => {
          const done = q.progress >= q.target;
          const pct = Math.round((100 * q.progress) / q.target);
          const shown = q.target >= 60 ? `${Math.floor(q.progress / 60)}/${q.target / 60} мин`.replace(' мин', state.lang === 'ru' ? ' мин' : ' min') : `${q.progress}/${q.target}`;
          const go = q.go.type === 'place' ? `/place/${q.go.id}` : q.go.type === 'friends' ? '/friends' : '/';
          return `<div class="card quest">${ORB_SVG(34)}<div class="grow stack" style="gap:8px"><b>${esc(t('q_' + q.id))}</b>
            <div class="row"><div class="meter grow"><i style="width:${pct}%"></i></div><span class="muted">${esc(shown)}</span></div></div>
            ${q.claimed ? `<span class="pill">${t('claimed')}</span>`
              : done ? `<button class="btn mint" data-claim="${q.id}">${esc(t('claim', q.reward))}</button>`
              : `<a class="btn ghost" href="${go}" data-link>${t('go')} · +${q.reward}</a>`}</div>`;
        }).join('')}</div>`;
      root.querySelectorAll('[data-claim]').forEach((b) => b.addEventListener('click', async () => {
        b.disabled = true;
        try { await api('POST', `/api/quests/${b.dataset.claim}/claim`); await refreshMe(); renderNav(location.pathname); draw(); }
        catch (e) { toast(e.message, 'error'); b.disabled = false; }
      }));
    };
    await draw();
  },

  async '/shop'(root) {
    if (!state.me) { sessionStorage.setItem('after_login', '/shop'); return go('/login'); }
    await refreshMe();
    let shop = await api('GET', '/api/shop');
    let tab = 'accessories';
    // Shirts: what there is to buy, and what of it is already yours.
    let clothing = { items: [], mine: new Set() };
    const loadClothing = async () => {
      const [all, mine] = await Promise.all([
        api('GET', '/api/clothing?sort=new'),
        api('GET', '/api/me/clothing').catch(() => ({ items: [] })),
      ]);
      const seen = new Map(all.items.map((c) => [c.id, c]));
      for (const c of mine.items) if (!seen.has(c.id)) seen.set(c.id, c);
      clothing = { items: [...seen.values()], mine: new Set(mine.items.map((c) => c.id)) };
    };
    await loadClothing();
    // What's on the preview: starts as what you wear.
    let look = { ...state.me, accessories: [...wornOf(state.me)], clothes: [...(state.me.clothes || [])] };
    const catalog = await loadAccessories();
    const slotOf = (id) => catalog.items?.find((i) => i.id === id)?.slot;
    root.innerHTML = `<h1>${t('shop')}</h1>
      <div class="shop">
        <div class="card shop-preview stack"><div class="viewer" id="tryon">${bust(state.me)}</div>
          <div class="row wrap-row">${walletChip()}</div>
          <button class="btn" id="savelook">${t('save_look')}</button></div>
        <div class="stack"><div class="tabs">${['accessories', 'faces_tab', 'clothing_tab'].map((k) => `<button data-tab="${k}" class="${k === tab ? 'on' : ''}">${t(k)}</button>`).join('')}</div>
          <div class="shop-grid" id="grid"></div></div></div>`;
    const preview = async () => {
      const el = $('#tryon');
      if (!el) return;
      el.innerHTML = '';
      el.classList.remove('live');
      await mellyViewer(el, look);
    };
    const name = (it) => (it.name ? it.name[state.lang] || it.name.en : it.id);
    // A shirt's picture is the whole template; the card shows the front of the torso,
    // which is the part people recognise it by.
    const clothTile = (c) => `<div class="cloth-tile" style="background-image:url('${esc(c.image)}')"></div>`;
    const drawClothing = () => {
      $('#grid').innerHTML = clothing.items.length ? clothing.items.map((c) => {
        const mine = clothing.mine.has(c.id) || c.creator?.id === state.me.id;
        const on = look.clothes.includes(c.id);
        const action = mine
          ? `<span class="pill">${t('owned')}</span>`
          : c.price > 0
            ? `<div class="buy-row"><button class="btn small" data-cbuy="${c.id}">${PIECE_SVG(16)}${c.price}</button></div>`
            : `<button class="btn small" data-cbuy="${c.id}">${t('take_free')}</button>`;
        return `<div class="card shop-item ${on ? 'on' : ''}">
          <div class="pic">${clothTile(c)}</div><b>${esc(c.name)}</b>
          <span class="muted" style="font-size:13px">${esc(c.creator?.display_name || '')}</span>
          ${action}<button class="btn small ghost" data-cwear="${c.id}">${on ? t('take_off') : mine ? t('wear') : t('try_on')}</button></div>`;
      }).join('') : `<div class="empty grow">${t('no_clothing_shop')}</div>`;
      $('#grid').querySelectorAll('[data-cwear]').forEach((b) => b.addEventListener('click', () => {
        const id = Number(b.dataset.cwear);
        look.clothes = look.clothes.includes(id) ? look.clothes.filter((x) => x !== id) : [...look.clothes, id].slice(-5);
        drawClothing();
        preview();
      }));
      $('#grid').querySelectorAll('[data-cbuy]').forEach((b) => b.addEventListener('click', async () => {
        b.disabled = true;
        try {
          const r = await api('POST', `/api/clothing/${b.dataset.cbuy}/buy`);
          state.me.wallet = r.wallet;
          await loadClothing();
          toast(t('bought'));
          renderNav(location.pathname);
          $('.shop-preview .wrap-row').innerHTML = walletChip();
          drawClothing();
        } catch (e) { toast(e.message, 'error'); b.disabled = false; }
      }));
    };
    const draw = () => {
      if (tab === 'clothing_tab') return drawClothing();
      const items = tab === 'accessories' ? shop.accessories : shop.faces;
      $('#grid').innerHTML = items.map((it) => {
        const worn = tab === 'accessories' ? look.accessories.includes(it.id) : look.face === it.id;
        // Faces are dark lines: show them on a skin-colored tile, the way they sit on the head.
        const pic = tab === 'faces_tab' ? `<img class="face-tile" style="background:${esc(state.me.colors?.head || '#f5f1ec')}" src="/img/faces/${FACE_SLUGS[it.id] || 'grin'}.png" alt="">` : `<img data-thumb="${esc(it.id)}" alt="">`;
        const action = it.owned || !it.price
          ? `<span class="pill">${it.price ? t('owned') : t('free')}</span>`
          : `<div class="buy-row">${buyButtons(it)}</div>`;
        return `<div class="card shop-item ${worn ? 'on' : ''}" data-item="${esc(it.id)}">
          <div class="pic">${pic}</div><b>${esc(tab === 'faces_tab' ? it.id : name(it))}</b>
          ${action}<button class="btn small ghost" data-try="${esc(it.id)}">${worn ? t('take_off') : it.owned || !it.price ? t('wear') : t('try_on')}</button></div>`;
      }).join('');
      $('#grid').querySelectorAll('img[data-thumb]').forEach((img) => accessoryThumb(img.dataset.thumb).then((url) => { if (url) img.src = url; }));
      $('#grid').querySelectorAll('[data-try]').forEach((b) => b.addEventListener('click', () => {
        const id = b.dataset.try;
        if (tab === 'faces_tab') look.face = look.face === id ? state.me.face : id;
        else if (look.accessories.includes(id)) look.accessories = look.accessories.filter((x) => x !== id);
        else look.accessories = [...look.accessories.filter((x) => slotOf(x) !== slotOf(id)), id].slice(-4);
        draw();
        preview();
      }));
      $('#grid').querySelectorAll('[data-buy]').forEach((b) => b.addEventListener('click', async () => {
        b.disabled = true;
        try {
          const r = await api('POST', '/api/shop/buy', { kind: tab === 'faces_tab' ? 'face' : 'accessory', id: b.dataset.buy, currency: b.dataset.cur });
          state.me.wallet = r.wallet;
          state.me.owned = r.owned;
          shop = await api('GET', '/api/shop');
          toast(t('bought'));
          renderNav(location.pathname);
          $('.shop-preview .wrap-row').innerHTML = walletChip();
          draw();
        } catch (e) { toast(e.message, 'error'); b.disabled = false; }
      }));
    };
    root.querySelectorAll('[data-tab]').forEach((b) => b.addEventListener('click', () => {
      tab = b.dataset.tab;
      root.querySelectorAll('[data-tab]').forEach((x) => x.classList.toggle('on', x === b));
      draw();
    }));
    $('#savelook').addEventListener('click', async () => {
      try {
        // Only what's yours can be saved; the rest was a fitting room.
        const keep = look.clothes.filter((id) => clothing.mine.has(id)
          || clothing.items.some((c) => c.id === id && c.creator?.id === state.me.id));
        if (keep.length !== look.clothes.length) toast(t('only_owned_clothes'));
        const { worn } = await api('PUT', '/api/me/clothing', { worn: keep });
        look.clothes = worn;
        const r = await api('PATCH', '/api/me', { accessories: look.accessories, face: look.face });
        r.user.clothes = worn;
        state.me = r.user;
        toast(t('look_saved'));
        try { await uploadMyBust(); renderNav(location.pathname); } catch {}
      } catch (e) { toast(e.message || t('only_owned'), 'error'); }
    });
    draw();
    preview();
  },

  async '/support'(root) {
    const legal = await api('GET', '/api/legal').catch(() => ({}));
    const mine = state.me ? (await api('GET', '/api/support').catch(() => ({ tickets: [] }))).tickets : [];
    root.innerHTML = `<h1>${t('support_title')}</h1><p class="muted">${t('support_text')}</p>
      <div class="grid2">
        <form class="card stack" id="ticket">
          <input name="subject" maxlength="120" placeholder="${t('subject')}" required>
          <textarea name="body" rows="6" maxlength="4000" placeholder="${t('message')}" required></textarea>
          <input name="contact" maxlength="120" placeholder="${t('contact')}" ${state.me ? '' : 'required'}>
          <div class="error"></div><button class="btn">${t('send_ticket')}</button></form>
        <div class="card stack"><h3>${t('support_other')}</h3>
          ${legal.support_email ? `<a href="mailto:${esc(legal.support_email)}">${esc(legal.support_email)}</a>` : ''}
          ${legal.support_telegram ? `<a href="https://t.me/${esc(legal.support_telegram.replace(/^@/, ''))}" target="_blank" rel="noopener">${esc(legal.support_telegram)}</a>` : ''}
          <a href="${TELEGRAM}" target="_blank" rel="noopener">t.me/meltiew</a>
          ${legal.operator_name ? `<span class="muted">${t('operator')}: ${esc(legal.operator_name)}${legal.operator_inn ? ', ИНН ' + esc(legal.operator_inn) : ''}</span>` : ''}
          <a href="/terms" data-link>${t('terms')}</a><a href="/privacy" data-link>${t('privacy_policy')}</a></div></div>
      ${mine.length ? `<h2>${t('my_tickets')}</h2><div class="stack">${mine.map((k) => `<div class="card stack"><div class="row"><b class="grow">${esc(k.subject)}</b>
        <span class="pill">${t(k.status === 'open' ? 'ticket_open' : 'ticket_closed')}</span></div><p style="white-space:pre-line;margin:0">${esc(k.body)}</p>
        ${k.reply ? `<div class="reply">${esc(k.reply)}</div>` : ''}<span class="muted">${esc(ago(k.created_at))}</span></div>`).join('')}</div>` : ''}`;
    $('#ticket').addEventListener('submit', async (e) => {
      e.preventDefault();
      const f = new FormData(e.target);
      try {
        await api('POST', '/api/support', { subject: f.get('subject'), body: f.get('body'), contact: f.get('contact') });
        toast(t('ticket_sent'));
        render();
      } catch (err) { $('.error', e.target).textContent = err.message; }
    });
  },

  async '/terms'(root) { await legalPage(root, 'terms'); },
  async '/privacy'(root) { await legalPage(root, 'privacy'); },
};

// --- gamepasses on the place page ----------------------------------------------------

async function passesBlock(box, p, mine) {
  const { passes } = await api('GET', `/api/places/${encodeURIComponent(p.id)}/passes`);
  if (!passes.length && !mine) { box.innerHTML = ''; return; }
  box.innerHTML = `<h2>${t('passes')}</h2>
    <div class="passes">${passes.length ? passes.map((ps) => `<div class="card pass">
      ${ps.image ? `<img src="${esc(ps.image)}" alt="">` : `<div class="pass-ph">${PIECE_SVG(44)}</div>`}
      <b>${esc(ps.name)}</b>${ps.description ? `<span class="muted">${esc(ps.description)}</span>` : ''}
      ${mine ? `<span class="muted">#${ps.id} · ${esc(t('pass_sales', ps.sales))}</span>` : ''}
      ${ps.owned ? `<span class="pill">${t('pass_owned')}</span>` : `<button class="btn small" data-pass="${ps.id}" data-name="${esc(ps.name)}" data-price="${ps.price}">${PIECE_SVG(16)} ${ps.price}</button>`}
      ${mine ? `<button class="link danger" data-delpass="${ps.id}">${t('pass_delete')}</button>` : ''}</div>`).join('') : `<div class="empty">${t('no_passes')}</div>`}</div>
    ${mine ? `<form class="card stack" id="newpass" style="margin-top:14px"><h3>${t('pass_add')}</h3><span class="muted">${esc(t('pass_hint'))}</span>
      <input name="name" maxlength="50" placeholder="${t('pass_name')}" required>
      <input name="price" type="number" min="1" max="100000" placeholder="${t('pass_price')}" required>
      <input name="description" maxlength="300" placeholder="${t('pass_desc')}">
      <label class="muted">${t('pass_image')} <input name="image" type="file" accept="image/png,image/jpeg"></label>
      <button class="btn">${t('pass_add')}</button></form>` : ''}`;
  const redraw = () => passesBlock(box, p, mine);
  box.querySelectorAll('[data-pass]').forEach((b) => b.addEventListener('click', async () => {
    if (!confirm(t('buy_pass_q', b.dataset.name, b.dataset.price))) return;
    try { const r = await api('POST', `/api/passes/${b.dataset.pass}/buy`); state.me.wallet = r.wallet; renderNav(location.pathname); toast(t('bought')); redraw(); }
    catch (e) { toast(e.message, 'error'); }
  }));
  box.querySelectorAll('[data-delpass]').forEach((b) => b.addEventListener('click', async () => {
    try { await api('DELETE', `/api/studio/places/${encodeURIComponent(p.id)}/passes/${b.dataset.delpass}`); redraw(); }
    catch (e) { toast(e.message, 'error'); }
  }));
  $('#newpass', box)?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const file = f.get('image');
    try {
      const image = file && file.size ? (await cropImage(file, [512, 512])) : undefined;
      await api('POST', `/api/studio/places/${encodeURIComponent(p.id)}/passes`, { name: f.get('name'), price: Number(f.get('price')), description: f.get('description'), image });
      redraw();
    } catch (err) { toast(err.message, 'error'); }
  });
}

// --- badges ------------------------------------------------------------------------------

const badgeTile = (b, showPlace) => `<div class="card badge-tile ${b.owned ? '' : 'dim'}" title="${esc(b.description || '')}">
  ${b.image ? `<img src="${esc(b.image)}" alt="">` : `<div class="badge-ph">★</div>`}
  <b>${esc(b.name)}</b>${showPlace && b.place_name ? `<a class="muted" href="/place/${encodeURIComponent(b.place_id)}" data-link>${esc(b.place_name)}</a>` : ''}</div>`;

// A place's badges: what you have is bright. The creator can add (up to 15) and delete.
async function badgesBlock(box, p, mine) {
  const { badges, max } = await api('GET', `/api/places/${encodeURIComponent(p.id)}/badges`);
  if (!badges.length && !mine) { box.innerHTML = ''; return; }
  box.innerHTML = `<h2>${t('badges')}</h2>
    <div class="badges">${badges.length ? badges.map((b) => `<div class="badge-wrap">${badgeTile(b, false)}
      ${mine ? `<span class="muted">#${b.id} · ${esc(t('badge_awarded', b.awarded))}</span><button class="link danger" data-delbadge="${b.id}">${t('pass_delete')}</button>` : ''}</div>`).join('') : `<div class="empty">${t('no_badges')}</div>`}</div>
    ${mine && badges.length < max ? `<form class="card stack" id="newbadge" style="margin-top:14px"><h3>${t('badge_add')}</h3><span class="muted">${esc(t('badge_hint'))}</span>
      <input name="name" maxlength="50" placeholder="${t('badge_name')}" required>
      <input name="description" maxlength="300" placeholder="${t('badge_desc')}">
      <label class="muted">${t('pass_image')} <input name="image" type="file" accept="image/png,image/jpeg"></label>
      <button class="btn">${t('badge_add')}</button></form>` : ''}`;
  const redraw = () => badgesBlock(box, p, mine);
  box.querySelectorAll('[data-delbadge]').forEach((b) => b.addEventListener('click', async () => {
    if (!confirm(t('badge_delete_q'))) return;
    try { await api('DELETE', `/api/studio/places/${encodeURIComponent(p.id)}/badges/${b.dataset.delbadge}`); redraw(); }
    catch (e) { toast(e.message, 'error'); }
  }));
  $('#newbadge', box)?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const file = f.get('image');
    try {
      const image = file && file.size ? (await cropImage(file, [512, 512])) : undefined;
      await api('POST', `/api/studio/places/${encodeURIComponent(p.id)}/badges`, { name: f.get('name'), description: f.get('description'), image });
      redraw();
    } catch (err) { toast(err.message, 'error'); }
  });
}

// --- admin: money, support -------------------------------------------------------------

async function adminEconomy(box) {
  const owner = state.me.role === 'owner';
  const r = await api('GET', '/api/admin/payments');
  const c = r.config || {};
  const L = r.legal || {};
  box.innerHTML = `
    ${owner ? `<form class="card stack" id="give"><h3>${t('adm_give')}</h3>
      <div class="row wrap-row"><input name="username" placeholder="${t('adm_give_user')}" required class="grow">
      <select name="currency"><option value="pieces">${t('pieces')}</option><option value="orbs">${t('orbs')}</option></select>
      <input name="delta" type="number" placeholder="${t('adm_amount')}" required class="grow"></div>
      <button class="btn">${t('adm_give_btn')}</button></form>` : ''}
    ${owner ? `<form class="card stack" id="paycfg"><h3>${t('adm_pay_cfg')}</h3>
      <label class="muted">${t('adm_api_key')} (${c.api_key_set ? t('adm_key_set') : t('adm_key_empty')})<input name="api_key" autocomplete="off" placeholder="rpk_live_..."></label>
      <label class="muted">${t('adm_secret')} (${c.secret_set ? t('adm_key_set') : t('adm_key_empty')})<input name="secret" type="password" autocomplete="off"></label>
      <label class="switch"><input type="checkbox" name="test" ${c.test ? 'checked' : ''}><i></i>${t('adm_test')}</label>
      <label class="muted">${t('adm_site')}<input name="site" value="${esc(c.site || '')}"></label>
      <span class="muted">${t('adm_callback')}: <code>${esc(c.callback || '')}</code></span>
      <h3>${t('adm_legal')}</h3>
      <input name="operator_name" value="${esc(L.operator_name)}" placeholder="${t('adm_operator')}">
      <input name="operator_inn" value="${esc(L.operator_inn)}" placeholder="${t('adm_inn')}">
      <input name="support_email" value="${esc(L.support_email)}" placeholder="${t('adm_email')}">
      <input name="support_telegram" value="${esc(L.support_telegram)}" placeholder="${t('adm_tg')}">
      <button class="btn">${t('save')}</button></form>` : ''}
    <div class="card stack"><h3>${t('adm_payments')}</h3><span class="muted">${esc(t('adm_total', r.totals.n, Math.round(r.totals.rub)))}</span>
      ${r.payments.map((p) => `<div class="row"><span class="grow">${esc(p.username)} · ${p.pieces} · ${esc(p.amount)} ₽</span><span class="pill">${esc(p.status)}</span><span class="muted">${esc(ago(p.created_at))}</span></div>`).join('')}</div>`;
  $('#give', box)?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    try {
      const w = await api('POST', '/api/admin/wallet', { username: f.get('username'), currency: f.get('currency'), delta: Number(f.get('delta')) });
      toast(`${f.get('username')}: ${piecesText(w.wallet)} / ${w.wallet.orbs}`);
      e.target.reset();
    } catch (err) { toast(err.message, 'error'); }
  });
  $('#paycfg', box)?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const body = Object.fromEntries(['api_key', 'secret', 'site', 'operator_name', 'operator_inn', 'support_email', 'support_telegram'].map((k) => [k, f.get(k) || '']));
    body.test = !!f.get('test');
    try { await api('POST', '/api/admin/payments/config', body); toast(t('saved')); adminEconomy(box); }
    catch (err) { toast(err.message, 'error'); }
  });
}

// Support inbox: requests from the site and letters to support@, each a conversation.
// Answers go out by email when there's an address; files open through the API (they
// need the staff login, so they're fetched and shown from memory).
async function apiBlob(path) {
  const res = await fetch(path, { headers: { 'x-client': 'web', ...(state.token ? { authorization: 'Bearer ' + state.token } : {}) } });
  if (!res.ok) throw new Error(res.statusText);
  return res.blob();
}

const fileSize = (n) => (n < 1024 ? `${n} B` : n < 1048576 ? `${Math.round(n / 1024)} KB` : `${(n / 1048576).toFixed(1)} MB`);

// Quoted history ("> ...") dimmed, the rest as is.
const letterHtml = (body) => esc(body).split('\n').map((l) => (l.startsWith('&gt;') ? `<span class="muted">${l}</span>` : l)).join('\n');

async function adminTickets(box) {
  const { tickets, address } = await api('GET', '/api/admin/tickets');
  const who = (k) => esc(k.name || k.username || k.contact || '—');
  box.innerHTML = `<span class="muted">${t('adm_mail_hint', address)}</span>
    ${tickets.length ? tickets.map((k) => `<button class="card stack ticket-row ${k.status === 'open' ? 'open' : ''}" data-open="${k.id}">
      <div class="row" style="gap:8px"><b class="grow">${esc(k.subject)}</b>
        ${k.source === 'email' ? `<span class="pill">✉ ${t('adm_by_mail')}</span>` : ''}
        <span class="pill">${t(k.status === 'open' ? 'ticket_open' : 'ticket_closed')}</span></div>
      <span class="muted">${who(k)}${k.mail_to && k.mail_to !== k.name ? ' · ' + esc(k.mail_to) : ''} · ${esc(ago(k.updated_at))}</span>
      <span class="muted ticket-snip">${esc(k.last || '')}</span></button>`).join('') : `<div class="empty">${t('adm_no_tickets')}</div>`}`;
  box.querySelectorAll('[data-open]').forEach((b) => b.addEventListener('click', () => adminTicket(box, b.dataset.open)));
}

async function adminTicket(box, id) {
  const { ticket: k, messages } = await api('GET', `/api/admin/tickets/${id}`);
  const person = esc(k.name || k.username || k.contact || '—');
  const open = k.status === 'open';
  box.innerHTML = `<div class="row"><button class="btn small ghost" id="tk-back">${t('back')}</button></div>
    <div class="card stack"><div class="row" style="gap:8px;flex-wrap:wrap"><h3 class="grow" style="margin:0">${esc(k.subject)}</h3>
      <span class="pill">${t(open ? 'ticket_open' : 'ticket_closed')}</span></div>
      <span class="muted">${person}${k.username ? ` · <a href="/u/${encodeURIComponent(k.username)}" data-link>@${esc(k.username)}</a>` : ''}${k.mail_to ? ' · ' + esc(k.mail_to) : ''}${k.contact && k.contact !== k.mail_to ? ' · ' + esc(k.contact) : ''}</span></div>
    ${messages.map((m) => `<div class="card stack ${m.dir === 'out' ? 'reply' : ''}">
      <span class="muted" style="font-size:14px">${m.dir === 'out' ? esc(m.author || 'Meltiew') : person} · ${esc(ago(m.created_at))}${m.emailed ? ' · ✉ ' + t('adm_emailed') : ''}</span>
      <div style="white-space:pre-wrap;overflow-wrap:anywhere">${letterHtml(m.body)}</div>
      ${m.files.length ? `<div class="row" style="flex-wrap:wrap;gap:8px">${m.files.map((f) => `<button class="btn small ghost" data-file="${m.id}/${f.n}" data-name="${esc(f.name)}">📎 ${esc(f.name)} <span class="muted">${fileSize(f.size)}</span></button>`).join('')}</div>
        <div class="row" style="flex-wrap:wrap;gap:8px">${m.files.filter((f) => f.image).map((f) => `<img data-img="${m.id}/${f.n}" alt="${esc(f.name)}" style="max-width:min(100%,360px);max-height:360px;border-radius:12px;display:none">`).join('')}</div>` : ''}</div>`).join('')}
    <form class="card stack" id="tk-form">
      <textarea name="reply" rows="5" maxlength="8000" placeholder="${t('adm_reply')}"></textarea>
      <span class="muted" style="font-size:14px">${k.mail_to ? t('adm_reply_mail', esc(k.mail_to)) : k.user_id ? t('adm_reply_site') : t('adm_reply_nowhere')}</span>
      <div class="row" style="flex-wrap:wrap;gap:8px">
        <button class="btn">${t('adm_send')}</button>
        <button type="button" class="btn ghost" id="tk-status">${t(open ? 'adm_close_only' : 'adm_reopen')}</button>
        <span class="grow"></span>
        ${k.mail_to ? `<button type="button" class="btn ghost" id="tk-spam">${t('adm_spam')}</button>` : ''}
        <button type="button" class="btn danger" id="tk-del">${t('delete')}</button></div></form>`;
  const back = () => adminTickets(box);
  $('#tk-back').addEventListener('click', back);
  // Pictures show under their letter; other files download.
  box.querySelectorAll('[data-img]').forEach(async (img) => {
    const [mid, n] = img.dataset.img.split('/');
    try { img.src = URL.createObjectURL(await apiBlob(`/api/admin/tickets/${k.id}/files/${mid}/${n}`)); img.style.display = ''; } catch {}
  });
  box.querySelectorAll('[data-file]').forEach((b) => b.addEventListener('click', async () => {
    try {
      const url = URL.createObjectURL(await apiBlob(`/api/admin/tickets/${k.id}/files/${b.dataset.file}`));
      const a = Object.assign(document.createElement('a'), { href: url, download: b.dataset.name });
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 10000);
    } catch (e) { toast(e.message, 'error'); }
  }));
  $('#tk-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const reply = e.target.reply.value.trim();
    if (!reply) return;
    const btn = e.submitter;
    if (btn) btn.disabled = true;
    try {
      const r = await api('POST', `/api/admin/tickets/${k.id}`, { reply, status: 'closed' });
      if (r.mail_error) toast(t('adm_mail_failed', r.mail_error), 'error');
      else toast(r.emailed ? t('adm_sent_mail') : t('saved'));
      pollCounts();
      adminTicket(box, k.id);
    } catch (err) { toast(err.message, 'error'); if (btn) btn.disabled = false; }
  });
  $('#tk-status').addEventListener('click', async () => {
    try { await api('POST', `/api/admin/tickets/${k.id}`, { status: open ? 'closed' : 'open' }); pollCounts(); back(); } catch (e) { toast(e.message, 'error'); }
  });
  $('#tk-spam')?.addEventListener('click', async () => {
    if (!confirm(t('adm_spam_q', k.mail_to))) return;
    try { await api('POST', `/api/admin/tickets/${k.id}/spam`); toast(t('done')); pollCounts(); back(); } catch (e) { toast(e.message, 'error'); }
  });
  $('#tk-del').addEventListener('click', async () => {
    if (!confirm(t('adm_delete_q'))) return;
    try { await api('DELETE', `/api/admin/tickets/${k.id}`); pollCounts(); back(); } catch (e) { toast(e.message, 'error'); }
  });
}

// --- legal pages -------------------------------------------------------------------------

async function legalPage(root, kind) {
  const L = await api('GET', '/api/legal').catch(() => ({}));
  const site = location.origin;
  const op = L.operator_name ? `${esc(L.operator_name)}${L.operator_inn ? `, ИНН ${esc(L.operator_inn)}` : ''}` : 'Администрация сервиса Meltiew';
  const contacts = [L.support_email && `почта: ${esc(L.support_email)}`, L.support_telegram && `Telegram: ${esc(L.support_telegram)}`, `форма обращения: <a href="/support" data-link>${esc(site)}/support</a>`].filter(Boolean).join('; ');
  const texts = { terms: LEGAL_TERMS, privacy: LEGAL_PRIVACY };
  root.innerHTML = `<article class="card legal">${texts[kind]({ op, contacts, site: esc(site) })}</article>`;
}

const LEGAL_TERMS = ({ op, contacts, site }) => `
<h1>Пользовательское соглашение (публичная оферта)</h1>
<p class="muted">Редакция от 26 сентября 2026 года</p>
<h2>1. Общие положения</h2>
<p>1.1. Настоящее соглашение регулирует отношения между ${op} (далее — «Оператор») и пользователем игровой платформы Meltiew: сайта ${site} и приложений Meltiew для Android, Windows и Linux (далее — «Сервис»).</p>
<p>1.2. Регистрация в Сервисе, использование Сервиса или оплата внутриигровой валюты означают полное и безоговорочное принятие этого соглашения (акцепт оферты). Если ты не согласен с условиями, не пользуйся Сервисом.</p>
<p>1.3. Сервис — платформа для создания и прохождения мини-игр («плейсов»), общения с друзьями и настройки персонажа.</p>
<h2>2. Аккаунт</h2>
<p>2.1. Для использования Сервиса нужен аккаунт. При регистрации указывается настоящая дата рождения: от неё зависят доступные функции общения.</p>
<p>2.2. Пользователи младше 14 лет пользуются Сервисом и совершают покупки только с согласия родителей или законных представителей. Покупки несовершеннолетних от 14 до 18 лет допускаются в пределах, разрешённых законом, в том числе на собственные средства.</p>
<p>2.3. Ты отвечаешь за сохранность пароля и за действия, совершённые в твоём аккаунте. Передавать аккаунт другим лицам нельзя.</p>
<h2>3. Правила поведения</h2>
<p>3.1. Запрещено: оскорбления, травля, угрозы, материалы сексуального характера, пропаганда насилия и запрещённых веществ, мошенничество, спам, выдача себя за других людей или администрацию, использование читов, ботов и уязвимостей, попытки получить чужие данные или доступ к чужому аккаунту.</p>
<p>3.2. Оператор вправе удалять контент, ограничивать общение, временно или навсегда блокировать аккаунты за нарушение этих правил.</p>
<h2>4. Пользовательский контент</h2>
<p>4.1. Плейсы, скрипты, изображения, комментарии и сообщения, которые ты публикуешь, остаются твоими. Публикуя их, ты разрешаешь Оператору безвозмездно хранить, показывать и распространять их внутри Сервиса.</p>
<p>4.2. Ты гарантируешь, что у тебя есть права на публикуемый контент и он не нарушает закон и права третьих лиц. Оператор вправе удалить любой контент, нарушающий соглашение.</p>
<h2>5. Внутриигровая валюта и покупки</h2>
<p>5.1. В Сервисе есть две внутриигровые валюты: «Кусочки» (покупаются за деньги) и «Опыт» (выдаётся бесплатно за активность: ежедневный заход и задания).</p>
<p>5.2. Кусочки — это не деньги и не электронные денежные средства. Покупая кусочки, ты получаешь право использовать их внутри Сервиса для получения цифровых товаров: аксессуаров, лиц персонажа, геймпассов плейсов и других функций. Кусочки нельзя вывести, обменять обратно на деньги или передать другому пользователю, кроме случаев, прямо предусмотренных Сервисом.</p>
<p>5.3. Цены наборов кусочков указаны в рублях на странице покупки до оплаты. Оплата принимается через платёжный сервис RollyPay (СБП, криптовалюта и другие доступные способы). Данные банковских карт Оператор не получает и не хранит.</p>
<p>5.4. Кусочки зачисляются на аккаунт автоматически после того, как платёжный сервис подтвердит оплату, обычно в течение нескольких минут. Если оплата прошла, а кусочки не пришли в течение часа, напиши в поддержку.</p>
<p>5.5. Возврат. Цифровой товар предоставляется сразу после оплаты. Неизрасходованные кусочки из покупки можно вернуть по заявке в поддержку в течение 14 дней с момента оплаты; потраченные кусочки возврату не подлежат, кроме случаев, предусмотренных законом. При отмене платежа банком (chargeback) или возврате средств соответствующее количество кусочков списывается с аккаунта.</p>
<p>5.6. Геймпассы — платные возможности внутри плейсов, которые создают авторы плейсов. Цена геймпасса указывается в кусочках; автор получает 95% цены в кусочках, 5% — комиссия Сервиса. За содержание и работу геймпасса отвечает автор плейса.</p>
<p>5.7. При блокировке аккаунта за нарушение соглашения кусочки и купленные вещи не компенсируются.</p>
<h2>6. Интеллектуальная собственность</h2>
<p>6.1. Программы, дизайн, персонаж Melly, логотипы и другие материалы Сервиса принадлежат Оператору. Копирование, продажа и распространение материалов Сервиса без разрешения запрещены.</p>
<h2>7. Ограничение ответственности</h2>
<p>7.1. Сервис предоставляется «как есть». Оператор старается, чтобы Сервис работал без перебоев, но не отвечает за временные сбои, технические работы, потерю соединения и обстоятельства вне его разумного контроля.</p>
<p>7.2. Оператор не отвечает за действия других пользователей и за контент, созданный пользователями, но реагирует на жалобы.</p>
<h2>8. Персональные данные</h2>
<p>8.1. Обработка персональных данных описана в <a href="/privacy" data-link>Политике конфиденциальности</a>.</p>
<h2>9. Изменение условий</h2>
<p>9.1. Оператор может изменять соглашение. Новая редакция публикуется на этой странице и действует с момента публикации. Продолжая пользоваться Сервисом, ты принимаешь новые условия.</p>
<h2>10. Контакты</h2>
<p>Оператор: ${op}. Связь: ${contacts}.</p>`;

const LEGAL_PRIVACY = ({ op, contacts, site }) => `
<h1>Политика конфиденциальности</h1>
<p class="muted">Редакция от 26 сентября 2026 года</p>
<h2>1. Общие положения</h2>
<p>1.1. Эта политика описывает, какие данные пользователей собирает и как обрабатывает ${op} (далее — «Оператор») в игровой платформе Meltiew: на сайте ${site} и в приложениях Meltiew (далее — «Сервис»).</p>
<p>1.2. Пользуясь Сервисом, ты соглашаешься с этой политикой. Если не согласен, не пользуйся Сервисом.</p>
<h2>2. Какие данные мы собираем</h2>
<p>— Данные аккаунта: логин, отображаемое имя, пароль (хранится только в виде хеша), дата рождения, настройки приватности.</p>
<p>— Профиль и персонаж: описание, цвета, лицо, аксессуары, изображение аватара.</p>
<p>— Общение: список друзей, заявки, блокировки, личные сообщения, сообщения игрового чата, комментарии, жалобы и обращения в поддержку.</p>
<p>— Контент: созданные плейсы, скрипты, загруженные изображения.</p>
<p>— Игровая активность: посещения плейсов, время игры, лайки, покупки внутри Сервиса, баланс кусочков и опыта.</p>
<p>— Платежи: номер заказа, сумма, статус оплаты. Данные банковских карт и счетов обрабатывает платёжный сервис RollyPay; Оператор их не получает и не хранит.</p>
<p>— Технические данные: IP-адрес, тип устройства и версия приложения, журналы работы сервера. На сайте токен входа и настройки хранятся в localStorage браузера.</p>
<h2>3. Зачем мы их обрабатываем</h2>
<p>Чтобы работали аккаунт и игры; чтобы показывать тебя друзьям и другим игрокам; чтобы применять возрастные правила общения (например, чат недоступен детям младше 13 лет, а сообщения фильтруются для несовершеннолетних); чтобы принимать оплату и зачислять покупки; чтобы разбирать жалобы, бороться с читерами и нарушителями; чтобы отвечать в поддержке и улучшать Сервис.</p>
<h2>4. Дети</h2>
<p>4.1. Дата рождения нужна, чтобы настроить общение безопасно. Детям младше 14 лет можно пользоваться Сервисом и совершать покупки только с согласия родителей или законных представителей.</p>
<p>4.2. Родители и законные представители могут запросить сведения об аккаунте ребёнка или его удаление через поддержку.</p>
<h2>5. Кому передаются данные</h2>
<p>5.1. Оператор не продаёт персональные данные. Данные передаются только: платёжному сервису — в объёме, нужном для проведения оплаты; хостинг-провайдеру, на серверах которого работает Сервис; государственным органам — в случаях, предусмотренных законом.</p>
<p>5.2. Другие игроки видят то, что публично по смыслу Сервиса: имя, аватар, профиль, статус в сети, созданные плейсы, сообщения в чате и комментарии. Список друзей можно скрыть в настройках.</p>
<h2>6. Хранение и защита</h2>
<p>6.1. Данные хранятся, пока существует аккаунт, и затем удаляются, кроме сведений, которые нужно хранить по закону (например, о платежах). Журналы сервера хранятся ограниченное время.</p>
<p>6.2. Оператор принимает разумные меры защиты: пароли хранятся в виде стойкого хеша, соединение шифруется, доступ к данным ограничен.</p>
<h2>7. Твои права</h2>
<p>Ты можешь узнать, какие данные о тебе хранятся, исправить их (большую часть — в настройках), попросить удалить аккаунт и данные, отозвать согласие на обработку. Для этого напиши в поддержку.</p>
<h2>8. Изменения</h2>
<p>Политика может обновляться, например из-за изменений закона или Сервиса. Новая редакция публикуется на этой странице.</p>
<h2>9. Контакты</h2>
<p>Оператор: ${op}. Связь: ${contacts}.</p>`;
