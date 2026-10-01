const cfg=window.ACCELARATE_CONFIG;
const sb=supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true}});
const root=document.getElementById('root');
const toastEl=document.getElementById('toast');
let session=null,state=null,uploading=false,selectedFile=null,selectedIndex=null;

function toast(m){toastEl.textContent=m;toastEl.classList.remove('hidden');setTimeout(()=>toastEl.classList.add('hidden'),3200)}
function escape(s){return String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}
function cardTone(i){if(i===12)return 'free';const r=Math.floor(i/5),c=i%5;return ((r+c)%2===0)?'blue':'white'}

async function ensureSession(){let {data}=await sb.auth.getSession();if(data.session){session=data.session;return}let r=await sb.auth.signInAnonymously({options:{data:{app:'accelarate-2026'}}});if(r.error)throw r.error;session=r.data.session}
async function api(action,payload={}){const {data}=await sb.auth.getSession();const token=data.session?.access_token;if(!token)throw new Error('Session expired');const r=await fetch(`${cfg.SUPABASE_URL}/functions/v1/game-api`,{method:'POST',headers:{'Content-Type':'application/json','apikey':cfg.SUPABASE_PUBLISHABLE_KEY,'Authorization':`Bearer ${token}`},body:JSON.stringify({action,...payload})});const j=await r.json();if(!r.ok||j.error)throw new Error(j.error||'Request failed');return j}
async function getPhotoUrl(path){if(!path)return null;const {data,error}=await sb.storage.from('selfies').createSignedUrl(path,3600);return error?null:data?.signedUrl||null}
async function loadState(){const id=localStorage.getItem('acc_player_id');if(!id)return false;try{state=await api('player_state',{player_id:id});return true}catch(e){localStorage.removeItem('acc_player_id');return false}}

function intro(){root.innerHTML=`<section class="panel"><h2>Join the game</h2><p class="muted">Enter your name. You’ll receive one of the five official ACCELARATE cards.</p><label class="sr-only" for="name">Your name</label><input id="name" class="input" maxlength="80" placeholder="Your name" autocomplete="name"><div style="height:10px"></div><button id="join" class="btn btn-primary">Start My Bingo</button><div style="height:12px"></div><div class="notice small">Your game session is saved on this phone. You do not need an email or account.</div></section>`;document.getElementById('join').onclick=join;document.getElementById('name').addEventListener('keydown',e=>{if(e.key==='Enter')join()})}
async function join(){const name=document.getElementById('name').value.trim();if(!name)return toast('Enter your name first.');const b=document.getElementById('join');b.disabled=true;b.textContent='Joining…';try{const j=await api('join',{player_name:name});localStorage.setItem('acc_player_id',j.player_id);await loadState();render()}catch(e){toast(e.message);b.disabled=false;b.textContent='Start My Bingo'}}

function render(){
  if(!state){intro();return}
  const completed=state.completedCount;const pct=Math.round(completed/24*100);const bingo=state.player.first_bingo_at;const blackout=state.player.blackout_claimed_at;
  root.innerHTML=`<section class="panel"><div class="row"><div class="grow"><b>${escape(state.player.display_name)}</b><div class="muted">Card #${state.card.card_number}</div></div><button id="refresh" class="btn btn-light" aria-label="Refresh game status">Refresh</button></div><div style="height:12px"></div><div class="stats"><div class="stat"><span class="muted">Selfies</span><b>${completed}/24</b></div><div class="stat"><span class="muted">Bingo</span><b>${bingo?'✓':'—'}</b></div><div class="stat"><span class="muted">Blackout</span><b>${blackout?'✓':'—'}</b></div><div class="stat"><span class="muted">Card</span><b>#${state.card.card_number}</b></div></div><div style="height:10px"></div><div class="progress" role="progressbar" aria-label="Selfie completion progress" aria-valuemin="0" aria-valuemax="24" aria-valuenow="${completed}"><span style="width:${pct}%"></span></div></section><section class="panel notice"><b>🎯 BINGO REQUIREMENT</b><div class="small">Complete <strong>one full horizontal row AND one full vertical column</strong>. BLACKOUT requires all 24 attendee squares; Free Space is automatic.</div></section>
  ${bingo?`<section class="panel success" aria-live="polite"><b>🎉 BINGO!</b><div class="small">First Bingo: ${new Date(bingo).toLocaleTimeString()} • ${escape(state.player.first_bingo_pattern||'Row + Column')}</div>${blackout?'':'<div class="small" style="margin-top:5px">Keep going — Blackout is still in the race.</div>'}</section>`:''}
  ${blackout?`<section class="panel warning" aria-live="polite"><b>👑 BLACKOUT CLAIMED</b><div class="small">Claim submitted at ${new Date(blackout).toLocaleTimeString()}. Organizer verification determines the Grand Prize winner.</div></section>`:`<section class="panel"><b>👑 Blackout race</b><div class="small muted">Complete all 24 attendee selfies. Free Space is automatic.</div></section>`}
  <section class="panel"><div class="board" role="grid" aria-label="ACCELARATE 2026 Bingo card">${state.squares.map((s,i)=>cell(s,i)).join('')}</div><p class="board-help">Tap a square to add its selfie. Choose <strong>Take Photo</strong> or <strong>Choose from Photos</strong>.</p></section>
  <section class="panel"><h3>🏆 Live Leaderboard</h3><div id="leaderboard" aria-live="polite"><span class="muted">Loading…</span></div></section>`;
  document.getElementById('refresh').onclick=async()=>{await loadState();render()};
  document.querySelectorAll('.cell[data-index]').forEach(el=>el.onclick=()=>openPhotoChooser(Number(el.dataset.index)));
  loadLeaderboard();setTimeout(refreshImages,100);
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
  const s=state.squares[index];if(!s||s.completed||s.is_free)return;
  selectedIndex=index;selectedFile=null;
  const label=escape(s.attendee_name);
  const modal=document.createElement('div');modal.className='modal';modal.id='photo-modal';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-labelledby','photo-title');
  modal.innerHTML=`<div class="modal-card"><h2 id="photo-title">Add selfie</h2><p class="modal-subtitle"><strong>${label}</strong><br><span class="muted">${escape(s.organization)}</span></p><p class="small">Choose how you want to add the photo. You can take a new selfie or select one from your photo library.</p><div class="choice-grid"><button id="take-photo" class="btn btn-primary choice-btn">📷 <span>Take Photo</span></button><button id="choose-photo" class="btn btn-light choice-btn">🖼️ <span>Choose from Photos</span></button></div><input id="camera-input" class="sr-only-file" type="file" accept="image/*" capture="user"><input id="library-input" class="sr-only-file" type="file" accept="image/*"><div id="preview-area" class="preview-area hidden"></div><div class="modal-actions"><button id="cancel-photo" class="btn btn-light">Cancel</button></div></div>`;
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
    uploading=true;toast('Uploading photo…');
    const blob=await compress(selectedFile);const user=(await sb.auth.getUser()).data.user;const playerId=state.player.id;const path=`${user.id}/${playerId}/${selectedIndex}.jpg`;
    const up=await sb.storage.from('selfies').upload(path,blob,{contentType:'image/jpeg',upsert:true});if(up.error)throw up.error;
    const result=await api('record_photo',{player_id:playerId,square_index:selectedIndex,storage_path:path});
    closePhotoChooser();await loadState();render();
    if(result.bingo_achieved)toast(`🎉 BINGO! ${result.bingo_pattern}`);else if(result.blackout_achieved)toast('👑 BLACKOUT CLAIMED! Organizer verification is next.');else toast('Photo saved!');
  }catch(e){toast(e.message)}finally{uploading=false}
}
function closePhotoChooser(){const m=document.getElementById('photo-modal');if(m)m.remove();selectedFile=null;selectedIndex=null}
async function compress(file){const img=new Image();const url=URL.createObjectURL(file);await new Promise((res,rej)=>{img.onload=res;img.onerror=rej;img.src=url});const max=1200,scale=Math.min(1,max/Math.max(img.width,img.height));const c=document.createElement('canvas');c.width=Math.round(img.width*scale);c.height=Math.round(img.height*scale);c.getContext('2d').drawImage(img,0,0,c.width,c.height);URL.revokeObjectURL(url);return await new Promise(r=>c.toBlob(r,'image/jpeg',.82))}
async function loadLeaderboard(){try{const rows=await api('leaderboard');const el=document.getElementById('leaderboard');if(!el)return;el.innerHTML=`<table class="leader"><thead><tr><th>Player</th><th>Bingo</th><th>Blackout</th></tr></thead><tbody>${rows.slice(0,15).map(r=>`<tr><td>${escape(r.display_name)} <span class="pill">Card ${r.card_number}</span></td><td>${r.first_bingo_at?new Date(r.first_bingo_at).toLocaleTimeString():'—'}</td><td>${r.blackout_status==='approved'?'👑 Verified':r.blackout_claimed_at?'🟡 Pending':'—'}</td></tr>`).join('')}</tbody></table>`}catch(e){}}
(async()=>{try{await ensureSession();if(await loadState()){render()}else intro()}catch(e){root.innerHTML=`<section class="panel danger">Unable to start the game: ${escape(e.message)}</section>`}})();
