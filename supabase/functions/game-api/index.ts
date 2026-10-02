import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const PUBLISHABLE_KEY = Deno.env.get('SUPABASE_PUBLISHABLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

async function caller(req: Request) {
  const auth = req.headers.get('Authorization') || ''
  const token = auth.replace(/^Bearer\s+/i, '')
  if (!token) throw new Error('Authentication required')
  const userClient = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data, error } = await userClient.auth.getUser(token)
  if (error || !data.user) throw new Error('Invalid session')
  return { user: data.user, userClient }
}

async function isAdmin(userId: string) {
  const { data, error } = await admin.from('admin_users').select('user_id,display_name').eq('user_id', userId).maybeSingle()
  if (error) throw error
  return data
}

async function playerState(userClient: any, playerId: string) {
  const { data: player, error: pErr } = await userClient
    .from('players')
    .select('id,display_name,card_id,game_id,joined_at,first_bingo_at,first_bingo_pattern,bingo_rejected,bingo_note,blackout_claimed_at,blackout_status,blackout_verified_at,blackout_note')
    .eq('id', playerId).single()
  if (pErr) throw pErr

  const { data: game, error: gErr } = await userClient
    .from('games').select('id,status').eq('id', player.game_id).single()
  if (gErr) throw gErr

  const { data: card, error: cErr } = await userClient
    .from('cards').select('id,card_number').eq('id', player.card_id).single()
  if (cErr) throw cErr

  const { data: defs, error: dErr } = await userClient
    .from('card_squares').select('square_index,attendee_name,organization,is_free').eq('card_id', player.card_id).order('square_index')
  if (dErr) throw dErr

  const { data: squares, error: sErr } = await userClient
    .from('player_squares').select('square_index,completed,photo_path,completed_at,is_free').eq('player_id', player.id).order('square_index')
  if (sErr) throw sErr

  const merged = (defs || []).map((d: any) => ({
    ...d,
    ...(squares || []).find((s: any) => s.square_index === d.square_index),
  }))

  return {
    player,
    game_status: game.status,
    card,
    squares: merged,
    completedCount: merged.filter((s: any) => s.completed && !s.is_free).length,
    bingo: !!player.first_bingo_at,
    blackout: !!player.blackout_claimed_at,
  }
}

async function leaderboard() {
  const { data: players, error } = await admin
    .from('players')
    .select('id,display_name,card_id,first_bingo_at,first_bingo_pattern,bingo_rejected,bingo_note,blackout_claimed_at,blackout_status,blackout_verified_at,joined_at')
    .eq('game_id', (await admin.from('games').select('id').eq('slug','accelarate-2026').single()).data?.id)
    .order('first_bingo_at', { ascending: true, nullsFirst: false })
  if (error) throw error

  const cardIds = [...new Set((players || []).map((p: any) => p.card_id))]
  const { data: cards, error: cardErr } = await admin.from('cards').select('id,card_number').in('id', cardIds.length ? cardIds : ['00000000-0000-0000-0000-000000000000'])
  if (cardErr) throw cardErr
  const cardMap = new Map((cards || []).map((c: any) => [c.id, c.card_number]))

  return (players || []).map((p: any, i: number) => ({
    ...p,
    card_number: cardMap.get(p.card_id),
    bingo_place: p.first_bingo_at ? i + 1 : null,
  }))
}

async function adminSnapshot() {
  const game = (await admin.from('games').select('*').eq('slug','accelarate-2026').single()).data
  const players = (await admin.from('players').select('id,display_name,card_id,joined_at,first_bingo_at,first_bingo_pattern,bingo_rejected,bingo_note,blackout_claimed_at,blackout_status,blackout_verified_at,blackout_note').eq('game_id',game.id).order('joined_at')).data || []
  const cardIds = [...new Set(players.map((p: any) => p.card_id))]
  const cards = (await admin.from('cards').select('id,card_number').in('id',cardIds.length ? cardIds : ['00000000-0000-0000-0000-000000000000'])).data || []
  const cardMap = new Map(cards.map((c: any) => [c.id,c.card_number]))

  const playerIds = players.map((p: any) => p.id)
  const squares = playerIds.length ? ((await admin.from('player_squares').select('player_id,square_index,completed,photo_path,completed_at,is_free').in('player_id',playerIds).order('square_index')).data || []) : []
  const definitions = cardIds.length ? ((await admin.from('card_squares').select('card_id,square_index,attendee_name,organization,is_free').in('card_id',cardIds)).data || []) : []

  const byPlayer = new Map<string, any[]>()
  for (const s of squares) {
    if (!byPlayer.has(s.player_id)) byPlayer.set(s.player_id, [])
    byPlayer.get(s.player_id)!.push(s)
  }
  const byCard = new Map<string, any[]>()
  for (const d of definitions) {
    if (!byCard.has(d.card_id)) byCard.set(d.card_id, [])
    byCard.get(d.card_id)!.push(d)
  }

  // Generate short-lived signed URLs only for organizer review.
  const verification = []
  for (const p of players.filter((x: any) => x.blackout_status === 'pending').sort((a: any,b: any) => new Date(a.blackout_claimed_at).getTime()-new Date(b.blackout_claimed_at).getTime())) {
    const ps = byPlayer.get(p.id) || []
    const urls: Record<string,string> = {}
    for (const s of ps.filter((x:any)=>x.photo_path)) {
      const { data } = await admin.storage.from('selfies').createSignedUrl(s.photo_path, 1800)
      if (data?.signedUrl) urls[String(s.square_index)] = data.signedUrl
    }
    verification.push({ player: {...p, card_number: cardMap.get(p.card_id)}, definitions: byCard.get(p.card_id) || [], squares: ps, signedPhotoUrls: urls })
  }

  return {
    game,
    players: players.map((p:any)=>({...p,card_number:cardMap.get(p.card_id),completedCount:(byPlayer.get(p.id)||[]).filter((s:any)=>s.completed&&!s.is_free).length})),
    verification,
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const body = await req.json()
    const action = body.action
    const { user, userClient } = await caller(req)

    if (action === 'join') {
      const name = String(body.player_name || '').trim()
      if (!name) return json({ error: 'Player name is required' }, 400)
      const { data, error } = await userClient.rpc('join_game', { p_player_name: name })
      if (error) throw error
      return json(data)
    }

    if (action === 'player_state') {
      return json(await playerState(userClient, body.player_id))
    }

    if (action === 'record_photo') {
      const playerId = String(body.player_id)
      const squareIndex = Number(body.square_index)
      const storagePath = String(body.storage_path || '')
      if (!storagePath) return json({ error: 'storage_path required' }, 400)
      const expectedPrefix = `${user.id}/${playerId}/`
      if (!storagePath.startsWith(expectedPrefix)) return json({ error: 'Invalid photo path' }, 403)
      const { data, error } = await userClient.rpc('record_photo', {
        p_player_id: playerId,
        p_square_index: squareIndex,
        p_photo_path: storagePath,
      })
      if (error) throw error
      return json(data)
    }

    if (action === 'leaderboard') {
      return json(await leaderboard())
    }

    if (action === 'admin_snapshot' || action === 'verify_blackout' || action === 'verify_bingo' || action === 'game_control') {
      const adminUser = await isAdmin(user.id)
      if (!adminUser) return json({ error: 'Organizer access required' }, 403)

      if (action === 'admin_snapshot') return json(await adminSnapshot())

      if (action === 'verify_bingo') {
        const playerId = String(body.player_id)
        const rejected = !!body.rejected
        const note = body.note ? String(body.note) : null
        const now = new Date().toISOString()
        const { data: player, error: pErr } = await admin.from('players')
          .select('id,game_id,display_name,first_bingo_at,first_bingo_pattern')
          .eq('id', playerId).single()
        if (pErr) throw pErr
        if (!player.first_bingo_at) return json({ error: 'No Bingo claim' }, 400)

        const { error: uErr } = await admin.from('players').update({
          bingo_rejected: rejected,
          bingo_note: rejected ? note : null
        }).eq('id', playerId)
        if (uErr) throw uErr

        const { error: eErr } = await admin.from('game_events').insert({
          game_id: player.game_id,
          player_id: playerId,
          event_type: rejected ? 'bingo_rejected' : 'bingo_reinstated',
          pattern: player.first_bingo_pattern,
          created_at: now,
          metadata: { rejected, note }
        })
        if (eErr) throw eErr
        return json({ player_id: playerId, bingo_rejected: rejected })
      }

      if (action === 'verify_blackout') {
        const playerId = String(body.player_id)
        const approved = !!body.approved
        const note = body.note ? String(body.note) : null
        const now = new Date().toISOString()
        const { data: player, error: pErr } = await admin.from('players').select('id,game_id,blackout_claimed_at').eq('id', playerId).single()
        if (pErr) throw pErr
        if (!player.blackout_claimed_at) return json({ error: 'No blackout claim' }, 400)
        if (approved) {
          const { data: earlier, error: earlierErr } = await admin.from('players')
            .select('id,display_name,blackout_claimed_at,blackout_status')
            .eq('game_id', player.game_id)
            .not('blackout_claimed_at','is',null)
            .lt('blackout_claimed_at', player.blackout_claimed_at)
            .neq('blackout_status','rejected')
            .order('blackout_claimed_at',{ascending:true})
            .limit(1)
          if (earlierErr) throw earlierErr
          if (earlier?.length) return json({ error: `An earlier Blackout claim exists for ${earlier[0].display_name}. Verify the earliest claim first.` }, 409)
        }
        const update = { blackout_status: approved ? 'approved' : 'rejected', blackout_verified_at: approved ? now : null, blackout_note: note }
        const { error: uErr } = await admin.from('players').update(update).eq('id', playerId)
        if (uErr) throw uErr
        const { error: eErr } = await admin.from('game_events').insert({ game_id: player.game_id, player_id: playerId, event_type: approved ? 'blackout_verified' : 'blackout_rejected', created_at: now, metadata: { approved, note } })
        if (eErr) throw eErr
        return json({ player_id: playerId, status: approved ? 'approved' : 'rejected' })
      }

      if (action === 'game_control') {
        const command = String(body.command)
        const status = command === 'open' ? 'open' : command === 'pause' ? 'paused' : command === 'close' ? 'closed' : null
        if (!status) return json({ error: 'Unsupported game command' }, 400)
        const { error } = await admin.from('games').update({ status, updated_at: new Date().toISOString() }).eq('slug','accelarate-2026')
        if (error) throw error
        return json({ status })
      }
    }

    return json({ error: 'Unknown action' }, 400)
  } catch (e) {
    console.error(e)
    return json({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})
