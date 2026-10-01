const cfg=window.ACCELARATE_CONFIG;
const sb=supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true}});
const root=document.getElementById('root');
const toastEl=document.getElementById('toast');
let snapshot=null;
let refreshTimer=null;
let loading=false;
let authReady=false;
let boardModal=null;

function toast(m){
  toastEl.textContent=m;
  toastEl.classList.remove('hidden');
  setTimeout(()=>toastEl.classList.add('hidden'),3500);
}

function clearRefreshTimer(){
  if(refreshTimer){clearInterval(refreshTimer);refreshTimer=null;}
}

function startRefreshTimer(){
  clearRefreshTimer();
  refreshTimer=setInterval(()=>{
    if(document.visibilityState==='visible' && authReady && !loading) load({fromTimer:true});
  },5000);
}

function apiErrorMessage(error){
  if(typeof error==='string') return error;
  if(error?.message) return error.message;
  if(error?.error) return typeof error.error==='string' ? error.error : JSON.stringify(error.error);
  try{return JSON.stringify(error)||'Request failed';}catch{return 'Request failed';}
}

async function api(action,payload={}){
  const {data,error:sessionError}=await sb.auth.getSession();
  if(sessionError) throw new Error(apiErrorMessage(sessionError));
  if(!data.session) throw new Error('Please sign in');

  const r=await fetch(`${cfg.SUPABASE_URL}/functions/v1/game-api`,{
    method:'POST',
    headers:{
      'Content-Type':'application/json',
      'apikey':cfg.SUPABASE_PUBLISHABLE_KEY,
      'Authorization':`Bearer ${data.session.access_token}`
    },
    body:JSON.stringify({action,...payload})
  });

  let j=null;
  try{j=await r.json();}catch{}
  if(!r.ok || j?.error){
    throw new Error(apiErrorMessage(j?.error || j || `Request failed (${r.status})`));
  }
  return j;
}

function login(message=''){
  clearRefreshTimer();
  authReady=false;
  root.innerHTML=`<section class="panel">
    <h2>Organizer sign in</h2>
    <p class="muted">Use the organizer Auth account created in Supabase.</p>
    ${message?`<div class="notice" style="margin-bottom:12px">${esc(message)}</div>`:''}
    <form id="loginForm" autocomplete="on">
      <label class="small muted" for="email">Email</label>
      <input id="email" name="email" class="input" placeholder="Organizer email" type="email" autocomplete="username" required>
      <div style="height:8px"></div>
      <label class="small muted" for="password">Password</label>
      <input id="password" name="password" class="input" placeholder="Password" type="password" autocomplete="current-password" required>
      <div style="height:10px"></div>
      <button id="login" class="btn btn-primary" type="submit">Sign in</button>
    </form>
  </section>`;

  document.getElementById('loginForm').onsubmit=async(e)=>{
    e.preventDefault();
    const button=document.getElementById('login');
    button.disabled=true;
    button.textContent='Signing in…';
    try{
      const email=document.getElementById('email').value.trim();
      const password=document.getElementById('password').value;
      const r=await sb.auth.signInWithPassword({email,password});
      if(r.error) throw r.error;

      // Do not replace the login form until the authenticated admin snapshot succeeds.
      authReady=true;
      const ok=await load({afterLogin:true});
      if(ok) startRefreshTimer();
    }catch(e){
      authReady=false;
      clearRefreshTimer();
      const msg=apiErrorMessage(e);
      toast(msg);
      login(msg);
    }finally{
      const current=document.getElementById('login');
      if(current){current.disabled=false;current.textContent='Sign in';}
    }
  };
}

function fmt(x){return x?new Date(x).toLocaleTimeString():'—'}


function closeBoardModal(){
  if(boardModal){boardModal.remove();boardModal=null;}
}

async function signedPhotoUrl(path){
  if(!path) return null;
  const {data,error}=await sb.storage.from('selfies').createSignedUrl(path,3600);
  if(error) throw error;
  return data?.signedUrl||null;
}

async function viewBoard(playerId){
  try{
    toast('Loading player board…');
    const {data,error}=await sb.rpc('admin_get_player_board',{p_player_id:playerId});
    if(error) throw error;
    if(!data) throw new Error('Board data not found');
    const defs=data.definitions||[];
    const sq=data.squares||[];
    const by=new Map(sq.map(x=>[x.square_index,x]));
    const urls={};
    for(const s of sq){
      if(s.photo_path) urls[s.square_index]=await signedPhotoUrl(s.photo_path);
    }
    const completed=sq.filter(x=>x.completed && !x.is_free).length;
    const bingo=data.player.first_bingo_at;
    const blackout=data.player.blackout_status;
    closeBoardModal();
    boardModal=document.createElement('div');
    boardModal.className='modal';
    boardModal.innerHTML=`<div class="modal-card board-modal-card" role="dialog" aria-modal="true" aria-labelledby="boardTitle">
      <div class="row"><div class="grow"><h2 id="boardTitle">${esc(data.player.display_name)}</h2><p class="modal-subtitle">Card #${data.player.card_number} • ${completed}/24 completed</p></div><button class="btn btn-light" id="closeBoard">Close</button></div>
      <div class="row" style="margin:10px 0 14px"><span class="pill ${bingo?'good':'warn'}">${bingo?'BINGO':'No Bingo'}</span><span class="pill ${blackout==='approved'?'good':blackout==='pending'?'warn':''}">${esc(blackout||'none').toUpperCase()}</span>${data.player.first_bingo_pattern?`<span class="small muted">${esc(data.player.first_bingo_pattern)}</span>`:''}</div>
      <div class="board inspection-board">${Array.from({length:25},(_,i)=>{const d=defs.find(x=>x.square_index===i)||{};const x=by.get(i)||{};const u=urls[i];return `<div class="inspect-cell ${d.is_free?'free':x.completed?'done':'not-done'}">${u?`<img src="${u}" alt="Selfie with ${esc(d.attendee_name||'attendee')}">`:''}<div class="inspect-overlay"><b>${d.is_free?'FREE SPACE':esc(d.attendee_name||'')}</b>${d.organization?`<span>${esc(d.organization)}</span>`:''}<em>${d.is_free?'Automatic':x.completed?`✓ ${fmt(x.completed_at)}`:'Not completed'}</em></div></div>`}).join('')}</div>
      <p class="board-help">Completed squares show the submitted selfie. Click a photo to view it larger.</p>
      <div style="height:10px"></div><div class="row"><span class="small muted">Joined: ${fmt(data.player.joined_at)}</span>${data.player.blackout_claimed_at?`<span class="small muted">Blackout claimed: ${fmt(data.player.blackout_claimed_at)}</span>`:''}</div>
    </div>`;
    document.body.appendChild(boardModal);
    document.getElementById('closeBoard').onclick=closeBoardModal;
    boardModal.addEventListener('click',e=>{if(e.target===boardModal)closeBoardModal();});
    boardModal.querySelectorAll('.inspect-cell img').forEach(img=>img.onclick=()=>showPhoto(img.src,img.alt));
  }catch(e){toast(apiErrorMessage(e));}
}

function showPhoto(src,alt){
  const m=document.createElement('div');m.className='modal';m.innerHTML=`<div class="modal-card photo-modal-card"><div class="row"><div class="grow"><h2>Submitted Selfie</h2><p class="modal-subtitle">${esc(alt)}</p></div><button class="btn btn-light" id="closePhoto">Close</button></div><img class="full-photo" src="${src}" alt="${esc(alt)}"></div>`;document.body.appendChild(m);document.getElementById('closePhoto').onclick=()=>m.remove();m.onclick=e=>{if(e.target===m)m.remove();};
}

async function resetGame(){
  const p=snapshot?.players||[];
  const events=snapshot?.events_count ?? 'unknown';
  const claims=p.filter(x=>x.blackout_claimed_at).length;
  const typed=prompt(`RESET ENTIRE GAME?\n\nThis will permanently remove ${p.length} player(s), their selfie progress, Bingo/Blackout results, and game events.\n\nYour five Bingo cards, attendee list, game configuration, and organizer accounts will remain.\n\nType RESET to continue.`);
  if(typed!=='RESET'){if(typed!==null)toast('Reset cancelled. You must type RESET exactly.');return;}
  try{
    const {data,error}=await sb.rpc('admin_reset_game');
    if(error) throw error;
    clearRefreshTimer();
    toast(`Game reset. ${data?.players_removed??p.length} player(s) removed.`);
    await load();
  }catch(e){toast(apiErrorMessage(e));}
}

function render(){
  const p=snapshot.players||[];
  const pending=snapshot.verification||[];
  const bingos=p.filter(x=>x.first_bingo_at).sort((a,b)=>new Date(a.first_bingo_at)-new Date(b.first_bingo_at));
  const approved=p.filter(x=>x.blackout_status==='approved').sort((a,b)=>new Date(a.blackout_verified_at)-new Date(b.blackout_verified_at));
  const winner=approved[0]||null;
  root.innerHTML=`<section class="panel">${winner?`<div class="panel success" style="margin:0 0 12px;padding:14px"><b>👑 BLACKOUT GRAND PRIZE WINNER</b><div class="small">${esc(winner.display_name)} • Card #${winner.card_number} • verified ${fmt(winner.blackout_verified_at)}</div><div class="small">The first approved Blackout is locked as the Grand Prize winner. Later Blackout claims remain recorded but cannot replace the verified winner.</div></div>`:''}<div class="notice" style="margin-bottom:12px"><b>🎯 Competition rules:</b> BINGO = <strong>one full horizontal row AND one full vertical column</strong>. BLACKOUT = <strong>all 24 attendee squares</strong>; Free Space is automatic.</div><div class="row"><div class="grow"><b>Game status:</b> <span class="pill ${snapshot.game.status==='open'?'good':'warn'}">${snapshot.game.status.toUpperCase()}</span></div><button class="btn btn-light" id="reload">Refresh</button><button class="btn btn-light" id="logout">Sign out</button></div><div style="height:12px"></div><div class="stats"><div class="stat"><span class="muted">Players</span><b>${p.length}</b></div><div class="stat"><span class="muted">Bingos</span><b>${bingos.length}</b></div><div class="stat"><span class="muted">Blackout claims</span><b>${p.filter(x=>x.blackout_claimed_at).length}</b></div><div class="stat"><span class="muted">Verified</span><b>${approved.length}</b></div></div><div style="height:12px"></div><div class="row"><button class="btn btn-gold" id="open">Open Game</button><button class="btn btn-light" id="pause">Pause</button><button class="btn btn-danger" id="close">Close</button><button class="btn btn-danger" id="resetGame">↻ Reset Game</button></div></section><section class="panel"><h2>📋 Player Boards</h2><p class="muted">Open any player's board to inspect every completed square and view the submitted selfies.</p>${tablePlayers(p)}</section><div class="admin-grid"><section class="panel"><h2>👑 Blackout Verification</h2>${pending.length?pending.map(renderVerification).join(''):`<div class="notice">No pending Blackout claims.</div>`}</section><section><section class="panel"><h2>🏆 Bingo Race</h2>${tableBingo(bingos)}</section><section class="panel"><h2>👑 Blackout Race</h2>${tableBlackout(p)}</section></section></div>`;
  document.getElementById('reload').onclick=()=>load();
  document.getElementById('logout').onclick=async()=>{clearRefreshTimer();authReady=false;await sb.auth.signOut();login()};document.getElementById('resetGame').onclick=resetGame;
  for(const id of ['open','pause','close'])document.getElementById(id).onclick=()=>control(id);
  document.querySelectorAll('[data-verify]').forEach(b=>b.onclick=()=>verify(b.dataset.verify,b.dataset.approved==='true'));document.querySelectorAll('[data-board]').forEach(b=>b.onclick=()=>viewBoard(b.dataset.board));
}

function tablePlayers(rows){return `<table class="leader"><thead><tr><th>Player</th><th>Card</th><th>Progress</th><th>Bingo</th><th>Blackout</th><th></th></tr></thead><tbody>${rows.map(r=>`<tr><td>${esc(r.display_name)}</td><td>${r.card_number}</td><td>${r.completedCount??'—'} / 24</td><td>${r.first_bingo_at?fmt(r.first_bingo_at):'—'}</td><td>${esc(r.blackout_status||'none')}</td><td><button class="btn btn-light" data-board="${r.id}">View Board</button></td></tr>`).join('')||'<tr><td colspan="6">No players yet.</td></tr>'}</tbody></table>`}
function tableBingo(rows){return `<table class="leader"><thead><tr><th>#</th><th>Player</th><th>Card</th><th>Time</th><th>Pattern</th></tr></thead><tbody>${rows.map((r,i)=>`<tr><td>${i+1}</td><td>${esc(r.display_name)}</td><td>${r.card_number}</td><td>${fmt(r.first_bingo_at)}</td><td>${esc(r.first_bingo_pattern||'')}</td></tr>`).join('')||'<tr><td colspan="5">No Bingo yet.</td></tr>'}</tbody></table>`}
function tableBlackout(rows){const claims=rows.filter(r=>r.blackout_claimed_at).sort((a,b)=>new Date(a.blackout_claimed_at)-new Date(b.blackout_claimed_at));return `<table class="leader"><thead><tr><th>#</th><th>Player</th><th>Claim</th><th>Status</th></tr></thead><tbody>${claims.map((r,i)=>`<tr><td>${i+1}</td><td>${esc(r.display_name)}</td><td>${fmt(r.blackout_claimed_at)}</td><td>${r.blackout_status}</td></tr>`).join('')||'<tr><td colspan="4">No Blackout claims yet.</td></tr>'}</tbody></table>`}
function renderVerification(v){const defs=v.definitions||[];const sq=v.squares||[];const by=new Map(sq.map(x=>[x.square_index,x]));return `<article class="verify-card"><div class="row"><div class="grow"><b>${esc(v.player.display_name)}</b><div class="muted">Card #${v.player.card_number} • Claimed ${fmt(v.player.blackout_claimed_at)}</div></div><span class="pill warn">PENDING</span></div><div class="verify-board">${Array.from({length:25},(_,i)=>{const d=defs.find(x=>x.square_index===i);const s=by.get(i);const u=v.signedPhotoUrls?.[i];return d?.is_free?`<div class="empty" style="display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:800">FREE</div>`:(u?`<img src="${u}" alt="${esc(d?.attendee_name)}">`:`<div class="empty" title="${esc(d?.attendee_name)}"></div>`)}).join('')}</div><div style="height:10px"></div><div class="small muted">Verification requires all 24 attendee squares to have valid selfies. The claim time is server-recorded.</div><div style="height:10px"></div><div class="row"><button class="btn btn-gold" data-verify="${v.player.id}" data-approved="true">✓ Approve Blackout</button><button class="btn btn-danger" data-verify="${v.player.id}" data-approved="false">Reject / Review</button></div></article>`}
async function verify(id,approved){const note=approved?'Verified by organizer':'Organizer rejected/reviewed claim';try{await api('verify_blackout',{player_id:id,approved,note});toast(approved?'Blackout verified.':'Blackout rejected.');await load()}catch(e){toast(apiErrorMessage(e))}}
async function control(id){const command=id==='open'?'open':id==='pause'?'pause':'close';try{await api('game_control',{command});toast(`Game ${command}ed.`);await load()}catch(e){toast(apiErrorMessage(e))}}
function esc(s){return String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}

async function load({afterLogin=false,fromTimer=false}={}){
  if(loading) return false;
  loading=true;
  try{
    snapshot=await api('admin_snapshot');
    authReady=true;
    render();
    if(!fromTimer) startRefreshTimer();
    return true;
  }catch(e){
    const msg=apiErrorMessage(e);
    console.error('Admin dashboard error:',e);

    // Only return to the login form when there is genuinely no session.
    const {data}=await sb.auth.getSession();
    if(!data.session){
      clearRefreshTimer();
      authReady=false;
      login(msg==='Please sign in'?'':msg);
    }else if(afterLogin){
      // Keep the login form stable if authentication succeeded but admin authorization/API failed.
      clearRefreshTimer();
      authReady=false;
      login(`Sign-in succeeded, but the organizer dashboard could not be loaded: ${msg}`);
    }else if(fromTimer){
      // Do not destroy the dashboard or recreate the login form because of a transient API error.
      toast(msg);
    }else{
      toast(msg);
    }
    return false;
  }finally{
    loading=false;
  }
}

sb.auth.onAuthStateChange((event,session)=>{
  if(event==='SIGNED_OUT' || !session){
    clearRefreshTimer();
    authReady=false;
    login();
  }
});

(async()=>{
  const {data,error}=await sb.auth.getSession();
  if(error){login(apiErrorMessage(error));return;}
  if(data.session){
    authReady=true;
    const ok=await load();
    if(!ok && !data.session) login();
  }else{
    login();
  }
})();
