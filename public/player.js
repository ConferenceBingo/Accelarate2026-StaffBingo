const cfg=window.ACCELARATE_CONFIG;
const sb=supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true}});
const root=document.getElementById('root');
const toastEl=document.getElementById('toast');
let session=null,state=null,uploading=false,selectedFile=null,selectedIndex=null,selectedReplacing=false,playerChannel=null,leaderboardTimer=null;

function toast(m){toastEl.textContent=m;toastEl.classList.remove('hidden');setTimeout(()=>toastEl.classList.add('hidden'),3200)}
function escape(s){return String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}
function cardTone(i){if(i===12)return 'free';const r=Math.floor(i/5),c=i%5;return ((r+c)%2===0)?'blue':'white'}

async function ensureSession({refresh=false}={}){
  let {data,error}=await sb.auth.getSession();
  if(error)throw error;
  if(data.session && !refresh){session=data.session;return session}
  if(data.session && refresh){
    const refreshed=await sb.auth.refreshSession();
    if(!refreshed.error && refreshed.data.session){session=refreshed.data.session;return session}
    // If refresh fails, keep the existing session when it is still present.
    session=data.session;
    return session;
  }
  const r=await sb.auth.signInAnonymously({options:{data:{app:'accelarate-2026'}}});
  if(r.error)throw r.error;
  session=r.data.session;
  return session;
}
async function api(action,payload={}){
  let s=await ensureSession();
  let r=await fetch(`${cfg.SUPABASE_URL}/functions/v1/game-api`,{method:'POST',headers:{'Content-Type':'application/json','apikey':cfg.SUPABASE_PUBLISHABLE_KEY,'Authorization':`Bearer ${s.access_token}`},body:JSON.stringify({action,...payload})});
  let j=null;try{j=await r.json()}catch{}
  // A stale anonymous access token can surface as a 401. Refresh the session once and retry.
  if(r.status===401){
    s=await ensureSession({refresh:true});
    r=await fetch(`${cfg.SUPABASE_URL}/functions/v1/game-api`,{method:'POST',headers:{'Content-Type':'application/json','apikey':cfg.SUPABASE_PUBLISHABLE_KEY,'Authorization':`Bearer ${s.access_token}`},body:JSON.stringify({action,...payload})});
    try{j=await r.json()}catch{}
  }
  if(!r.ok||j?.error){
    const err=typeof j?.error==='string'?j.error:j?.error?.message||JSON.stringify(j?.error)||`Request failed (${r.status})`;
    throw new Error(err);
  }
  return j;
}
async function getPhotoUrl(path){if(!path)return null;const {data,error}=await sb.storage.from('selfies').createSignedUrl(path,3600);return error?null:data?.signedUrl||null}

// Read the canonical game status directly from Supabase. This prevents an older
// Edge Function deployment from making the player page appear stuck in PAUSED.
async function getCanonicalGameStatus(){
  const s=await ensureSession({refresh:true});
  const url=`${cfg.SUPABASE_URL}/rest/v1/games?slug=eq.accelarate-2026&select=status,updated_at`;
  const r=await fetch(url,{headers:{'apikey':cfg.SUPABASE_PUBLISHABLE_KEY,'Authorization':`Bearer ${s.access_token}`}});
  let j=null;try{j=await r.json()}catch{}
  if(!r.ok) throw new Error(typeof j?.message==='string'?j.message:`Unable to read game status (${r.status})`);
  const row=Array.isArray(j)?j[0]:null;
  if(!row?.status) throw new Error('Game status could not be read. Tap Refresh and try again.');
  return row.status;
}

async function syncCanonicalGameStatus(){
  if(!state)return false;
  try{
    state.game_status=await getCanonicalGameStatus();
    return true;
  }catch(e){
    return false;
  }
}
async function loadState(){const id=localStorage.getItem('acc_player_id');if(!id)return false;try{await ensureSession({refresh:true});state=await api('player_state',{player_id:id});await syncCanonicalGameStatus();return true}catch(e){toast(e.message);return false}}
function subscribeToPlayer(){
  if(playerChannel){sb.removeChannel(playerChannel);playerChannel=null}
  const id=state?.player?.id;if(!id)return;
  playerChannel=sb.channel(`acc-player-${id}`).on('postgres_changes',{event:'UPDATE',schema:'public',table:'players',filter:`id=eq.${id}`},async payload=>{
    const previous=state?.player?.blackout_status;
    const previousBingoRejected=!!state?.player?.bingo_rejected;
    if(await loadState()){
      render();
      const status=state?.player?.blackout_status;
      if(status==='rejected' && previous!=='rejected') toast('⚠️ Your Blackout submission was not accepted. Please review the message on your board.');
      if(status==='approved' && previous!=='approved') toast('👑 Your Blackout submission was approved!');
      const bingoRejected=!!state?.player?.bingo_rejected;
      if(bingoRejected && !previousBingoRejected) toast('⚠️ Your Bingo submission was not accepted. Please review the message on your board.');
      if(!bingoRejected && previousBingoRejected) toast('✅ Your Bingo status was restored by the organizer.');
    }
  }).subscribe();
}

function intro(){root.innerHTML=`<section class="panel"><h2>Join the game</h2><p class="muted">Enter your name. You’ll receive one of the five official ACCELARATE cards.</p><label class="sr-only" for="name">Your name</label><input id="name" class="input" maxlength="80" placeholder="Your name" autocomplete="name"><div style="height:10px"></div><button id="join" class="btn btn-primary">Start My Bingo</button><div style="height:12px"></div><div class="notice small">Your game session is saved on this phone. You do not need an email or account.</div></section>`;document.getElementById('join').onclick=join;document.getElementById('name').addEventListener('keydown',e=>{if(e.key==='Enter')join()})}
async function join(){const name=document.getElementById('name').value.trim();if(!name)return toast('Enter your name first.');const b=document.getElementById('join');b.disabled=true;b.textContent='Joining…';try{const j=await api('join',{player_name:name});localStorage.setItem('acc_player_id',j.player_id);await loadState();render()}catch(e){toast(e.message);b.disabled=false;b.textContent='Start My Bingo'}}

function render(){
  if(!state){intro();return}
  const completed=state.completedCount;const pct=Math.round(completed/24*100);const bingo=state.player.first_bingo_at;const blackout=state.player.blackout_claimed_at;
  root.innerHTML=`<section class="panel"><div class="row"><div class="grow"><b>${escape(state.player.display_name)}</b><div class="muted">Card #${state.card.card_number}</div></div><button id="refresh" class="btn btn-light" aria-label="Refresh game status">Refresh</button></div><div style="height:12px"></div><div class="stats"><div class="stat"><span class="muted">Selfies</span><b>${completed}/24</b></div><div class="stat"><span class="muted">Bingo</span><b>${bingo?'✓':'—'}</b></div><div class="stat"><span class="muted">Blackout</span><b>${blackout?'✓':'—'}</b></div><div class="stat"><span class="muted">Card</span><b>#${state.card.card_number}</b></div></div><div style="height:10px"></div><div class="progress" role="progressbar" aria-label="Selfie completion progress" aria-valuemin="0" aria-valuemax="24" aria-valuenow="${completed}"><span style="width:${pct}%"></span></div></section><section class="panel notice"><b>🎯 BINGO REQUIREMENT</b><div class="small">Complete <strong>one full horizontal row AND one full vertical column</strong>. BLACKOUT requires all 24 attendee squares; Free Space is automatic.</div></section>
  ${state.game_status!=='open'?`<section class="panel warning" aria-live="polite"><b>⏸️ GAME ${escape(String(state.game_status||'paused').toUpperCase())}</b><div class="small">The organizer has temporarily stopped new submissions. Your progress is saved. When the organizer reopens the game, tap <strong>Refresh</strong> and you can continue with the same card and progress.</div></section>`:''}
  ${state.player.bingo_rejected?`<section class="panel danger" aria-live="assertive"><b>⚠️ BINGO SUBMISSION NOT ACCEPTED</b><div class="small">Your Bingo submission was reviewed and was not accepted by the organizer.</div>${state.player.bingo_note?`<div class="small" style="margin-top:6px"><strong>Organizer note:</strong> ${escape(state.player.bingo_note)}</div>`:''}<div class="small" style="margin-top:6px">Your completed squares are still saved.</div><div style="height:10px"></div><button id="resubmit-bingo" class="btn btn-primary">✓ Board Ready — Resubmit Bingo</button></section>`:bingo?`<section class="panel success" aria-live="polite"><b>🎉 BINGO!</b><div class="small">First Bingo: ${new Date(bingo).toLocaleTimeString()} • ${escape(state.player.first_bingo_pattern||'Row + Column')}</div>${blackout?'':'<div class="small" style="margin-top:5px">Keep going — Blackout is still in the race.</div>'}</section>`:''}
  ${state.player.blackout_status==='rejected'?`<section class="panel danger" aria-live="assertive"><b>⚠️ BLACKOUT SUBMISSION NOT ACCEPTED</b><div class="small">Your Blackout submission was reviewed and was not accepted by the organizer.</div>${state.player.blackout_note?`<div class="small" style="margin-top:6px"><strong>Organizer note:</strong> ${escape(state.player.blackout_note)}</div>`:''}<div class="small" style="margin-top:6px">Your completed squares are still saved.</div><div style="height:10px"></div><button id="resubmit-blackout" class="btn btn-primary">✓ Board Ready — Resubmit Blackout</button></section>`:blackout?`<section class="panel warning" aria-live="polite"><b>👑 BLACKOUT CLAIMED</b><div class="small">Claim submitted at ${new Date(blackout).toLocaleTimeString()}. Organizer verification determines the Grand Prize winner.</div></section>`:`<section class="panel"><b>👑 Blackout race</b><div class="small muted">Complete all 24 attendee selfies. Free Space is automatic.</div></section>`}
  <section class="panel"><div class="board" role="grid" aria-label="ACCELARATE 2026 Bingo card">${state.squares.map((s,i)=>cell(s,i)).join('')}</div><p class="board-help">Tap a square to add its selfie. Choose <strong>Take Photo</strong> or <strong>Choose from Photos</strong>.</p></section>
  <section class="panel"><h3>🏆 Live Leaderboard</h3><div id="leaderboard" aria-live="polite"><span class="muted">Loading…</span></div></section>`;
  document.getElementById('refresh').onclick=async()=>{await loadState();render()};
  const rb=document.getElementById('resubmit-bingo'); if(rb) rb.onclick=()=>resubmitBingo();
  const ro=document.getElementById('resubmit-blackout'); if(ro) ro.onclick=()=>resubmitBlackout();
  document.querySelectorAll('.cell[data-index]').forEach(el=>el.onclick=()=>openPhotoChooser(Number(el.dataset.index)));
  subscribeToPlayer();
  loadLeaderboard();
  if(leaderboardTimer)clearTimeout(leaderboardTimer);
  const scheduleLeaderboardRefresh=()=>{leaderboardTimer=setTimeout(async()=>{if(document.visibilityState==='visible')await loadLeaderboard();scheduleLeaderboardRefresh()},5000)};
  scheduleLeaderboardRefresh();
  setTimeout(refreshImages,100);
}

function cell(s,i){
  const tone=cardTone(i);
  if(s.is_free)return `<button class="cell free" disabled aria-label="Free Space. Automatically completed."><div class="cell-content"><div class="name">FREE SPACE</div><div class="org">ACCELARATE 2026</div><div class="prompt">Automatically completed</div></div></button>`;
  const completed=s.completed;
  return `<button class="cell ${tone} ${completed?'done':''}" data-index="${i}" role="gridcell" aria-label="${escape(s.attendee_name)}. ${escape(s.organization)}. ${completed?'Completed. Tap to view your photo.':'Tap to add a selfie.'}">${s.photo_path?`<img id="photo-${i}" class="thumb" alt="Selfie with ${escape(s.attendee_name)}">`:''}<span class="status-badge" aria-hidden="true">${completed?'✓':'📷'}</span><div class="cell-content"><div class="name">${escape(s.attendee_name)}</div><div class="org">${escape(s.organization)}</div><div class="prompt">${completed?'Selfie added':'Meet & mark'}</div></div></button>`
}
async function refreshImages(){for(const s of state.squares){if(s.photo_path){const u=await getPhotoUrl(s.photo_path);const img=document.getElementById(`photo-${s.square_index}`);if(img&&u)img.src=u}}}

function openPhotoChooser(index){
  if(uploading)return;
  const s=state.squares[index];if(!s||s.is_free)return;
  if(s.completed){
    const replace=window.confirm(`A photo is already saved for ${s.attendee_name}.\n\nDo you want to replace the saved photo?`);
    if(!replace)return;
  }
  selectedIndex=index;selectedFile=null;selectedReplacing=!!s.completed;
  const replacing=selectedReplacing;
  const label=escape(s.attendee_name);
  const modal=document.createElement('div');modal.className='modal';modal.id='photo-modal';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-labelledby','photo-title');
  modal.innerHTML=`<div class="modal-card"><h2 id="photo-title">${replacing?'Replace selfie':'Add selfie'}</h2><p class="modal-subtitle"><strong>${label}</strong><br><span class="muted">${escape(s.organization)}</span></p><p class="small">${replacing?'Choose a new photo to replace the one currently saved.':'Choose how you want to add the photo. You can take a new selfie or select one from your photo library.'}</p><div class="choice-grid"><button id="take-photo" class="btn btn-primary choice-btn">📷 <span>Take Photo</span></button><button id="choose-photo" class="btn btn-light choice-btn">🖼️ <span>Choose from Photos</span></button></div><input id="camera-input" class="sr-only-file" type="file" accept="image/*" capture="user"><input id="library-input" class="sr-only-file" type="file" accept="image/*"><div id="preview-area" class="preview-area hidden"></div><div class="modal-actions"><button id="cancel-photo" class="btn btn-light">Cancel</button></div></div>`;
  document.body.appendChild(modal);
  const camera=document.getElementById('camera-input'),library=document.getElementById('library-input');
  document.getElementById('take-photo').onclick=()=>camera.click();
  document.getElementById('choose-photo').onclick=()=>library.click();
  camera.onchange=()=>handleChosenFile(camera.files?.[0]);
  library.onchange=()=>handleChosenFile(library.files?.[0]);
  document.getElementById('cancel-photo').onclick=closePhotoChooser;
  modal.addEventListener('click',e=>{if(e.target===modal)closePhotoChooser()});
}

async function handleChosenFile(file){
  if(!file)return;
  if(!file.type.startsWith('image/')){toast('Please choose an image.');return}
  selectedFile=file;
  const previewArea=document.getElementById('preview-area');if(!previewArea)return;
  const url=URL.createObjectURL(file);
  previewArea.classList.remove('hidden');
  previewArea.innerHTML=`<img src="${url}" alt="Selected selfie preview"><div class="small">Does this photo show you with the attendee?</div><div class="preview-actions"><button id="use-photo" class="btn btn-primary">✓ Use This Photo</button><button id="retake-photo" class="btn btn-light">Choose Again</button></div>`;
  document.getElementById('use-photo').onclick=()=>saveSelectedPhoto();
  document.getElementById('retake-photo').onclick=()=>{previewArea.classList.add('hidden');previewArea.innerHTML='';selectedFile=null};
}

async function saveSelectedPhoto(){
  if(!selectedFile||selectedIndex===null||uploading)return;
  try{
    uploading=true;
    // Refresh the player's server state before uploading. If the organizer has closed/paused
    // the game, stop here so the browser never attempts an RLS-protected upload that cannot be recorded.
    await loadState();
    if(!state){throw new Error('Your game session could not be restored. Tap Refresh and try again.')}
    await syncCanonicalGameStatus();
    if(state.game_status!=='open'){
      closePhotoChooser();
      render();
      toast('The game is currently closed/paused. Your progress is saved. Tap Refresh after the organizer reopens it.');
      return;
    }
    await ensureSession({refresh:true});
    toast('Uploading photo…');
    const blob=await compress(selectedFile);
    const user=(await sb.auth.getUser()).data.user;
    if(!user)throw new Error('Your game session expired. Tap Refresh and try again.');
    const playerId=state.player.id;
    const path=`${user.id}/${playerId}/${selectedIndex}.jpg`;
    const up=await sb.storage.from('selfies').upload(path,blob,{contentType:'image/jpeg',upsert:true});
    if(up.error){
      // Refresh the auth session once if storage rejects a stale session, then retry the upload.
      await ensureSession({refresh:true});
      const retry=await sb.storage.from('selfies').upload(path,blob,{contentType:'image/jpeg',upsert:true});
      if(retry.error)throw retry.error;
    }
    const result=await api(selectedReplacing?'replace_photo':'record_photo',{player_id:playerId,square_index:selectedIndex,storage_path:path});
    closePhotoChooser();await loadState();render();
    if(result.bingo_achieved)toast(`🎉 BINGO! ${result.bingo_pattern}`);else if(result.blackout_achieved)toast('👑 BLACKOUT CLAIMED! Organizer verification is next.');else toast('Photo saved!');
  }catch(e){toast(e.message)}finally{uploading=false}
}
function closePhotoChooser(){const m=document.getElementById('photo-modal');if(m)m.remove();selectedFile=null;selectedIndex=null;selectedReplacing=false}
async function compress(file){const img=new Image();const url=URL.createObjectURL(file);await new Promise((res,rej)=>{img.onload=res;img.onerror=rej;img.src=url});const max=1200,scale=Math.min(1,max/Math.max(img.width,img.height));const c=document.createElement('canvas');c.width=Math.round(img.width*scale);c.height=Math.round(img.height*scale);c.getContext('2d').drawImage(img,0,0,c.width,c.height);URL.revokeObjectURL(url);return await new Promise(r=>c.toBlob(r,'image/jpeg',.82))}

async function resubmitBingo(){
  if(uploading)return;
  if(!state?.player?.bingo_rejected)return;
  if(state.game_status!=='open'){toast('The game is currently closed/paused. Tap Refresh after the organizer reopens it.');return}
  if(!window.confirm('Submit your current board for Bingo verification again? The new submission will receive a new server timestamp.'))return;
  try{
    const data=await api('player_resubmit_bingo',{player_id:state.player.id});
    await loadState();render();toast(`🎉 Bingo resubmitted — ${data.bingo_pattern||state.player.first_bingo_pattern||'Row + Column'}`);
  }catch(e){toast(e.message||'Unable to resubmit Bingo.')}
}
async function resubmitBlackout(){
  if(uploading)return;
  if(state?.player?.blackout_status!=='rejected')return;
  if(state.game_status!=='open'){toast('The game is currently closed/paused. Tap Refresh after the organizer reopens it.');return}
  if(!window.confirm('Submit your current completed board for Blackout verification again? The new submission will receive a new server timestamp.'))return;
  try{
    await api('player_resubmit_blackout',{player_id:state.player.id});
    await loadState();render();toast('👑 Blackout resubmitted for organizer verification.');
  }catch(e){toast(e.message||'Unable to resubmit Blackout.')}
}
async function loadLeaderboard(){
  const el=document.getElementById('leaderboard');
  if(!el)return;
  try{
    // Use the authenticated leaderboard action that is present in every
    // deployed version of game-api. The player already has an authenticated
    // session, so this avoids a separate unauthenticated public action that
    // can fail with "Authentication required" when an older Edge Function is
    // still deployed.
    const rows=await api('leaderboard');
    const list=(Array.isArray(rows)?rows:[]).map(r=>{
      const bingo = r.bingo_status || (r.first_bingo_at ? (r.bingo_rejected ? 'rejected' : 'submitted') : 'pending');
      const blackout = r.blackout_status_public || (r.blackout_claimed_at ? (r.blackout_status==='approved' ? 'approved' : r.blackout_status==='rejected' ? 'rejected' : 'submitted') : 'pending');
      return {...r,bingo_status:bingo,blackout_status_public:blackout};
    });
    const statusPill=(status)=>{
      const cls=status==='approved'?'good':status==='rejected'?'bad':status==='submitted'?'submitted':'pending';
      const label=status==='approved'?'Approved':status==='rejected'?'Rejected':status==='submitted'?'Submitted':'Pending';
      return `<span class="pill ${cls}">${label}</span>`;
    };
    el.innerHTML=`<div class="small muted" style="margin-bottom:6px">Live standings • updates automatically</div><table class="leader"><thead><tr><th>Player</th><th>Bingo</th><th>Blackout</th></tr></thead><tbody>${list.map(r=>`<tr><td>${escape(r.display_name)} <span class="pill">Card ${escape(r.card_number)}</span></td><td>${statusPill(r.bingo_status)}</td><td>${statusPill(r.blackout_status_public)}</td></tr>`).join('')||'<tr><td colspan="3">No players yet.</td></tr>'}</tbody></table>`;
  }catch(e){
    console.error('Leaderboard refresh failed:',e);
    el.innerHTML=`<div class="notice">Leaderboard temporarily unavailable. Retrying automatically…<div class="small" style="margin-top:6px">${escape(e.message||'Unknown error')}</div></div>`;
  }
}
(async()=>{try{await ensureSession();if(await loadState()){render()}else intro()}catch(e){root.innerHTML=`<section class="panel danger">Unable to start the game: ${escape(e.message)}</section>`}})();
