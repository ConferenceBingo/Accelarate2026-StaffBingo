-- ACCELARATE 2026 Multiplayer Bingo
-- Run this whole file in the Supabase SQL editor.

create extension if not exists pgcrypto;

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  status text not null default 'setup' check (status in ('setup','open','paused','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Normalize the status constraint when this migration is rerun against an earlier version.
do $$
begin
  begin
    alter table public.games drop constraint if exists games_status_check;
  exception when undefined_object then null;
  end;
  alter table public.games
    add constraint games_status_check check (status in ('setup','open','paused','closed'));
  alter table public.games alter column status set default 'setup';
end $$;


insert into public.games (slug,title,status)
values ('accelarate-2026','ACCELARATE 2026 Networking Bingo','setup')
on conflict (slug) do nothing;

create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  card_number int not null,
  created_at timestamptz not null default now(),
  unique(game_id, card_number)
);

create table if not exists public.card_squares (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  square_index int not null check (square_index between 0 and 24),
  attendee_name text,
  organization text,
  is_free boolean not null default false,
  unique(card_id, square_index)
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  auth_user_id uuid not null unique,
  display_name text not null check (char_length(display_name) between 1 and 80),
  card_id uuid not null references public.cards(id),
  joined_at timestamptz not null default now(),
  first_bingo_at timestamptz,
  first_bingo_pattern text,
  blackout_claimed_at timestamptz,
  blackout_verified_at timestamptz,
  blackout_status text not null default 'none' check (blackout_status in ('none','pending','approved','rejected')),
  blackout_note text
);

create table if not exists public.player_squares (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  square_index int not null check (square_index between 0 and 24),
  is_free boolean not null default false,
  completed boolean not null default false,
  photo_path text,
  completed_at timestamptz,
  unique(player_id, square_index)
);

create table if not exists public.blackout_claims (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  claimed_at timestamptz not null default clock_timestamp(),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  verified_at timestamptz,
  note text,
  unique(player_id)
);

create table if not exists public.game_events (
  id bigint generated always as identity primary key,
  game_id uuid not null references public.games(id) on delete cascade,
  player_id uuid references public.players(id) on delete set null,
  event_type text not null,
  square_index int,
  pattern text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_players_game on public.players(game_id);
create index if not exists idx_players_card on public.players(card_id);
create index if not exists idx_player_squares_player on public.player_squares(player_id);
create index if not exists idx_events_game_created on public.game_events(game_id, created_at);

-- Seed the five supplied cards. The source PDF has 25 positions per card,
-- with the center position (index 12) as FREE SPACE.

create schema if not exists private;
create table if not exists private.acc_seed(card_number int, square_index int, attendee_name text, organization text, is_free boolean, primary key(card_number,square_index));
truncate table private.acc_seed;
insert into private.acc_seed(card_number, square_index, attendee_name, organization, is_free) values
-- Card 1
(1,0,'Bryan Frazar','Louisville-Jefferson County Metro Government, KY',false),(1,1,'Heather Mompean','Stockton, CA - City of',false),(1,2,'Guchun Huang','Martin, FL - County of',false),(1,3,'Laura Newton','Colorado Springs, CO - City of',false),(1,4,'Andrea Webster','Fort Lauderdale, FL - City of',false),
(1,5,'Jared Moyer','State of Michigan - Department of Licensing and Regulatory Affairs (LARA)',false),(1,6,'Richard Vallejos','San Mateo County Planning and Building',false),(1,7,'Taylor Hunter','Paradise Valley, AZ - Town of',false),(1,8,'Desman Ford','Fort Lauderdale, FL - City of',false),(1,9,'Chris Melvin','Buncombe, NC - County of',false),
(1,10,'Orlando Pereira','San Bernardino, CA - County of',false),(1,11,'Karen Riley-Olms','Monterey, CA - County of',false),(1,12,null,'ACCELARATE 2026',true),(1,13,'John Bennett','Michigan - State of',false),(1,14,'Tremaine Yarbrough','Torrance, CA - City of',false),
(1,15,'Wadnerson Boileau','Manatee, FL - County of',false),(1,16,'Andrew Harrington','North Port, FL - City of',false),(1,17,'Janet Martin','Boise, ID - City of',false),(1,18,'Rene Martinez Jr.','Moreno Valley, CA - City of',false),(1,19,'Bhandhavya Nadagoud','San Leandro, CA - City of',false),
(1,20,'Melissa Willard','Roseville, CA - City of',false),(1,21,'Angel Roberts','Humboldt County Department of Health & Human Services',false),(1,22,'Amber Stout','Menifee, CA - City of',false),(1,23,'Nisha Padiyar','Mecklenburg, NC - County of',false),(1,24,'Nachendra Bellur','Anaheim, CA - City of',false),
-- Card 2
(2,0,'Derrick Moon','Washington, OR - County of',false),(2,1,'Connor Rhodes','Tempe, AZ, City of - Tax and Business License Department',false),(2,2,'Jess Irving','San Mateo, CA - County of',false),(2,3,'Heather Mompean','Stockton, CA - City of',false),(2,4,'Janet Martin','Boise, ID - City of',false),
(2,5,'Kelly Holliday','Weld, CO - County of',false),(2,6,'Annie He','Santa Clara, CA - City of',false),(2,7,'Richard Vallejos','San Mateo County Planning and Building',false),(2,8,'Karen Riley-Olms','Monterey, CA - County of',false),(2,9,'May Tran','Hillsboro, OR - City of',false),
(2,10,'Eric Britt','Hall, GA - County of',false),(2,11,'Greg Lee','Chesapeake, VA - City of',false),(2,12,null,'ACCELARATE 2026',true),(2,13,'David Boucher','Pinellas, FL - County of',false),(2,14,'Kevin Ferguson','Hillsboro, OR - City of',false),
(2,15,'Angel Roberts','Humboldt County Department of Health & Human Services',false),(2,16,'Rosa Espinoza','Goodyear Development Services Department, AZ',false),(2,17,'Brian MacDermott','Boise, ID - City of',false),(2,18,'Amber Stout','Menifee, CA - City of',false),(2,19,'Taylor Hunter','Paradise Valley, AZ - Town of',false),
(2,20,'Monica Monge Chavez','Napa, CA - County',false),(2,21,'Guchun Huang','Martin, FL - County of',false),(2,22,'Jennifer DeCory','Clearwater, FL - City of',false),(2,23,'Sharmin Kamal','Washoe, NV - County of',false),(2,24,'Joshua Peterson','Butte, CA - County of',false),
-- Card 3
(3,0,'Jordan Smith','Napa, CA - County of',false),(3,1,'Janet Martin','Boise, ID - City of',false),(3,2,'Rene Martinez Jr.','Moreno Valley, CA - City of',false),(3,3,'Jennifer Trujillo','Jurupa Valley Development Services, CA',false),(3,4,'Ashman Deokar','Pinal, AZ - County of',false),
(3,5,'Steve Lavey','Torrance, CA - City of',false),(3,6,'Angel Roberts','Humboldt County Department of Health & Human Services',false),(3,7,'Shannon Dale','Salt Lake City, UT - City of',false),(3,8,'Jared Moyer','State of Michigan - Department of Licensing and Regulatory Affairs (LARA)',false),(3,9,'Theresa Armstrong','Bradenton, FL - City of',false),
(3,10,'Monica Monge Chavez','Napa, CA - County',false),(3,11,'Connor Rhodes','Tempe, AZ, City of - Tax and Business License Department',false),(3,12,null,'ACCELARATE 2026',true),(3,13,'Omar Soto','Mesa, AZ - City of',false),(3,14,'June Miyamoto','Oakland, CA - City of',false),
(3,15,'Guchun Huang','Martin, FL - County of',false),(3,16,'Sean Winfield','CAGIS, OH (Cincinnati Area Geographic Information System)',false),(3,17,'Sharmin Kamal','Washoe, NV - County of',false),(3,18,'Jess Irving','San Mateo, CA - County of',false),(3,19,'Julia Connally','Fremont, CA - City of',false),
(3,20,'Carlos Ruiz','Palo Alto, CA - City of',false),(3,21,'Nicole Folman','Santa Barbara, CA - City of',false),(3,22,'Wadnerson Boileau','Manatee, FL - County of',false),(3,23,'Bryan Frazar','Louisville-Jefferson County Metro Government, KY',false),(3,24,'Karen Riley-Olms','Monterey, CA - County of',false),
-- Card 4
(4,0,'Patrick Miner','Butte, CA - County of',false),(4,1,'LaDonna Crum','Jefferson, AL - County of',false),(4,2,'Jared Moyer','State of Michigan - Department of Licensing and Regulatory Affairs (LARA)',false),(4,3,'Janet Martin','Boise, ID - City of',false),(4,4,'Eileen Koo','Contra Costa, CA - County of',false),
(4,5,'Jessica Setiawan','Palo Alto Planning & Development Department, CA',false),(4,6,'Shannon Dale','Salt Lake City, UT - City of',false),(4,7,'Serete Itebete','Monterey County Health Dept, Environmental Health Bureau',false),(4,8,'Kristopher Green','Denver, CO - City and County of',false),(4,9,'Alan Redbourn','Clackamas, OR - County of',false),
(4,10,'Rosa Espinoza','Goodyear Development Services Department, AZ',false),(4,11,'Brian MacDermott','Boise, ID - City of',false),(4,12,null,'ACCELARATE 2026',true),(4,13,'Jordan Smith','Napa, CA - County of',false),(4,14,'Joshua Davidson','Humboldt, CA - County of',false),
(4,15,'Joshua Peterson','Butte, CA - County of',false),(4,16,'Guchun Huang','Martin, FL - County of',false),(4,17,'Karen Riley-Olms','Monterey, CA - County of',false),(4,18,'Nisha Padiyar','Mecklenburg, NC - County of',false),(4,19,'Dick Murdock','North Port, FL - City of',false),
(4,20,'Carlos Ruiz','Palo Alto, CA - City of',false),(4,21,'Theresa Armstrong','Bradenton, FL - City of',false),(4,22,'Steve Lavey','Torrance, CA - City of',false),(4,23,'Regina Benson','Sarasota, FL - County of',false),(4,24,'Eric Britt','Hall, GA - County of',false),
-- Card 5
(5,0,'Janet Martin','Boise, ID - City of',false),(5,1,'Kristopher Green','Denver, CO - City and County of',false),(5,2,'Bhandhavya Nadagoud','San Leandro, CA - City of',false),(5,3,'Ty Gonzalez','Colorado Springs, CO - City of',false),(5,4,'Carmen Nieves','Polk, FL - County of',false),
(5,5,'Nachendra Bellur','Anaheim, CA - City of',false),(5,6,'Steve Lavey','Torrance, CA - City of',false),(5,7,'Joshua Davidson','Humboldt, CA - County of',false),(5,8,'Julia Connally','Fremont, CA - City of',false),(5,9,'Nelson Mendez Droney','DeLand, FL - City of',false),
(5,10,'Dick Murdock','North Port, FL - City of',false),(5,11,'Tremaine Yarbrough','Torrance, CA - City of',false),(5,12,null,'ACCELARATE 2026',true),(5,13,'Chris Melvin','Buncombe, NC - County of',false),(5,14,'Sean Winfield','CAGIS, OH (Cincinnati Area Geographic Information System)',false),
(5,15,'Johnny Terfehr','Eastvale, CA - City of',false),(5,16,'Tom Richards','Brookline, MA - Town of',false),(5,17,'Amber Stout','Menifee, CA - City of',false),(5,18,'Desman Ford','Fort Lauderdale, FL - City of',false),(5,19,'Mary Braun','Chino, CA - City of',false),
(5,20,'Shannon Dale','Salt Lake City, UT - City of',false),(5,21,'Jess Irving','San Mateo, CA - County of',false),(5,22,'Chi Tran','Fremont, CA - City of',false),(5,23,'Rosa Espinoza','Goodyear Development Services Department, AZ',false),(5,24,'Carlos Ruiz','Palo Alto, CA - City of',false)
);
insert into public.cards(game_id,card_number)
select g.id,s.card_number from public.games g join (select distinct card_number from private.acc_seed) s on true
where g.slug='accelarate-2026'
on conflict (game_id,card_number) do nothing;

insert into public.card_squares(card_id,square_index,attendee_name,organization,is_free)
select c.id,s.square_index,s.attendee_name,s.organization,s.is_free
from public.cards c join public.games g on g.id=c.game_id
join private.acc_seed s on s.card_number=c.card_number
on conflict (card_id,square_index) do update set attendee_name=excluded.attendee_name, organization=excluded.organization, is_free=excluded.is_free;

-- Private selfie bucket, limited to image types and 5 MB.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('selfies','selfies',false,5242880,array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/heic'];

alter table public.games enable row level security;
alter table public.cards enable row level security;
alter table public.card_squares enable row level security;
alter table public.players enable row level security;
alter table public.player_squares enable row level security;
alter table public.blackout_claims enable row level security;
alter table public.game_events enable row level security;
alter table public.admin_users enable row level security;

-- Idempotent RLS policies.
do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname in ('public','storage')
      and (
        (schemaname='public' and tablename in ('cards','card_squares','games','players','player_squares','game_events','admin_users','blackout_claims'))
        or (schemaname='storage' and tablename='objects')
      )
  loop
    execute format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end $$;

-- Public read-only access to card definitions and game state.
create policy "card definitions readable" on public.cards for select to authenticated using (true);
create policy "square definitions readable" on public.card_squares for select to authenticated using (true);
create policy "game readable" on public.games for select to authenticated using (true);

create policy "player sees own player row" on public.players for select to authenticated using (auth_user_id = auth.uid());
create policy "player sees own squares" on public.player_squares for select to authenticated
using (player_id in (select id from public.players where auth_user_id=auth.uid()));
create policy "player sees own blackout claim" on public.blackout_claims for select to authenticated
using (player_id in (select id from public.players where auth_user_id=auth.uid()));

-- Admins can read all operational data.
create policy "admins read players" on public.players for select to authenticated
using (exists(select 1 from public.admin_users a where a.user_id=auth.uid()));
create policy "admins read player squares" on public.player_squares for select to authenticated
using (exists(select 1 from public.admin_users a where a.user_id=auth.uid()));
create policy "admins read events" on public.game_events for select to authenticated
using (exists(select 1 from public.admin_users a where a.user_id=auth.uid()));
create policy "admins read admins" on public.admin_users for select to authenticated
using (user_id=auth.uid());
create policy "admins read blackout claims" on public.blackout_claims for select to authenticated
using (exists(select 1 from public.admin_users a where a.user_id=auth.uid()));

-- Storage: players can upload only into their own auth-user folder.
create policy "player uploads own selfies" on storage.objects for insert to authenticated
with check (bucket_id='selfies' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "player reads own selfies" on storage.objects for select to authenticated
using (bucket_id='selfies' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "player deletes own selfies" on storage.objects for delete to authenticated
using (bucket_id='selfies' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "admins read selfies" on storage.objects for select to authenticated
using (bucket_id='selfies' and exists(select 1 from public.admin_users a where a.user_id=auth.uid()));


-- Atomic player join / card assignment.
create or replace function public.join_game(p_player_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game games;
  v_player players;
  v_card cards;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if trim(coalesce(p_player_name,'')) = '' then raise exception 'Player name is required'; end if;

  select * into v_game
  from games
  where slug='accelarate-2026'
  for update;

  if not found then raise exception 'Game not configured'; end if;
  if v_game.status <> 'open' then raise exception 'Game is not open'; end if;

  select * into v_player
  from players
  where auth_user_id=auth.uid() and game_id=v_game.id;

  if found then
    return jsonb_build_object(
      'player_id',v_player.id,
      'card_number',(select card_number from cards where id=v_player.card_id),
      'display_name',v_player.display_name
    );
  end if;

  select c.* into v_card
  from cards c
  left join players p on p.card_id=c.id and p.game_id=v_game.id
  where c.game_id=v_game.id
  group by c.id
  order by count(p.id), random()
  limit 1;

  if not found then raise exception 'No bingo cards are configured'; end if;

  insert into players(game_id,auth_user_id,display_name,card_id)
  values(v_game.id,auth.uid(),trim(p_player_name),v_card.id)
  returning * into v_player;

  insert into player_squares(player_id,square_index,is_free,completed,completed_at)
  select v_player.id,s.square_index,s.is_free,s.is_free,
         case when s.is_free then clock_timestamp() else null end
  from card_squares s
  where s.card_id=v_card.id;

  insert into game_events(game_id,player_id,event_type,metadata)
  values(v_game.id,v_player.id,'player_joined',jsonb_build_object('card_number',v_card.card_number));

  return jsonb_build_object(
    'player_id',v_player.id,
    'card_number',v_card.card_number,
    'display_name',v_player.display_name
  );
end;
$$;

-- Record a completed selfie and calculate Bingo / Blackout atomically.
-- Bingo requires BOTH at least one complete horizontal row AND one complete vertical column.
create or replace function public.record_photo(
  p_player_id uuid,
  p_square_index int,
  p_photo_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player players;
  v_game games;
  v_now timestamptz := clock_timestamp();
  v_row_complete boolean := false;
  v_col_complete boolean := false;
  v_bingo boolean := false;
  v_pattern text := null;
  v_blackout boolean := false;
  v_row int;
  v_col int;
  v_i int;
  v_all boolean := false;
  v_bingo_at timestamptz;
  v_blackout_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_photo_path is null or trim(p_photo_path) = '' then raise exception 'Photo path is required'; end if;

  select * into v_player
  from players
  where id=p_player_id and auth_user_id=auth.uid()
  for update;

  if not found then raise exception 'Player session not found'; end if;

  select * into v_game from games where id=v_player.game_id;
  if v_game.status <> 'open' then raise exception 'Game is not open'; end if;

  if p_square_index = 12 then raise exception 'Free Space is automatic'; end if;
  if p_square_index < 0 or p_square_index > 24 then raise exception 'Invalid square'; end if;

  if not exists(
    select 1 from card_squares
    where card_id=v_player.card_id
      and square_index=p_square_index
      and not is_free
  ) then
    raise exception 'Invalid card square';
  end if;

  -- The storage policy also requires the first path segment to be the current auth user.
  if (storage.foldername(p_photo_path))[1] <> auth.uid()::text then
    raise exception 'Photo path does not belong to this player';
  end if;

  update player_squares
  set completed=true,
      photo_path=p_photo_path,
      completed_at=coalesce(completed_at,v_now)
  where player_id=v_player.id
    and square_index=p_square_index
    and not completed;

  -- Check all 5 rows.
  for v_i in 0..4 loop
    if not exists(
      select 1 from player_squares
      where player_id=v_player.id
        and square_index between v_i*5 and v_i*5+4
        and completed
    ) then
      continue;
    end if;
    v_row_complete := true;
    v_row := v_i + 1;
    exit;
  end loop;

  -- Check all 5 columns.
  for v_i in 0..4 loop
    if not exists(
      select 1 from player_squares
      where player_id=v_player.id
        and square_index % 5 = v_i
        and completed
    ) then
      continue;
    end if;
    v_col_complete := true;
    v_col := v_i;
    exit;
  end loop;

  v_bingo := v_row_complete and v_col_complete;

  if v_bingo and v_player.first_bingo_at is null then
    v_pattern := 'Row ' || v_row || ' + Column ' || chr(66+v_col);
    update players
    set first_bingo_at=v_now,
        first_bingo_pattern=v_pattern
    where id=v_player.id;

    insert into game_events(game_id,player_id,event_type,pattern,created_at,metadata)
    values(
      v_player.game_id,v_player.id,'bingo',v_pattern,v_now,
      jsonb_build_object('row',v_row,'column',chr(66+v_col))
    );
    v_bingo_at := v_now;
  elsif v_bingo then
    v_pattern := coalesce(
      v_player.first_bingo_pattern,
      'Row ' || v_row || ' + Column ' || chr(66+v_col)
    );
  end if;

  -- A blackout is 24 attendee squares complete; Free Space is already complete.
  select not exists(
    select 1
    from player_squares
    where player_id=v_player.id
      and completed=false
      and not is_free
  ) into v_all;

  if v_all and v_player.blackout_claimed_at is null then
    v_blackout_at := v_now;

    insert into blackout_claims(game_id,player_id,claimed_at,status)
    values(v_player.game_id,v_player.id,v_now,'pending')
    on conflict (player_id) do nothing;

    if found then
      update players
      set blackout_claimed_at=v_now,
          blackout_status='pending'
      where id=v_player.id;

      insert into game_events(game_id,player_id,event_type,created_at,metadata)
      values(
        v_player.game_id,v_player.id,'blackout_claimed',v_now,
        jsonb_build_object('claim_id',(select id from blackout_claims where player_id=v_player.id))
      );
      v_blackout := true;
    else
      v_blackout_at := null;
    end if;
  end if;

  return jsonb_build_object(
    'player_id',v_player.id,
    'square_index',p_square_index,
    'completed_at',v_now,
    'bingo_achieved',v_bingo_at is not null,
    'bingo_at',v_bingo_at,
    'bingo_pattern',v_pattern,
    'row_complete',v_row_complete,
    'column_complete',v_col_complete,
    'blackout_achieved',v_blackout,
    'blackout_at',v_blackout_at,
    'completed_count',(
      select count(*) from player_squares
      where player_id=v_player.id and completed and not is_free
    ),
    'full_count',(
      select count(*) from player_squares
      where player_id=v_player.id and not is_free
    )
  );
end;
$$;

-- Admin controls the authoritative game state.
create or replace function public.admin_set_game_status(
  p_game_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_game games;
begin
  if not exists(select 1 from admin_users where user_id=auth.uid()) then
    raise exception 'Admin access required';
  end if;

  if p_status not in ('setup','open','paused','closed') then
    raise exception 'Invalid game status';
  end if;

  update games
  set status=p_status, updated_at=clock_timestamp()
  where id=p_game_id
  returning * into v_game;

  if not found then raise exception 'Game not found'; end if;

  insert into game_events(game_id,event_type,created_at,metadata)
  values(
    p_game_id,'game_status_changed',clock_timestamp(),
    jsonb_build_object('status',p_status)
  );

  return jsonb_build_object(
    'game_id',v_game.id,
    'status',v_game.status,
    'updated_at',v_game.updated_at
  );
end;
$$;

-- Admin verification. Rejected claims remain in the audit trail, so the next
-- chronologically eligible pending claim can be reviewed.
create or replace function public.admin_verify_blackout(
  p_player_id uuid,
  p_approved boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_player players;
  v_claim blackout_claims;
  v_now timestamptz := clock_timestamp();
begin
  if not exists(select 1 from admin_users where user_id=auth.uid()) then
    raise exception 'Admin access required';
  end if;

  select * into v_player from players where id=p_player_id for update;
  if not found then raise exception 'Player not found'; end if;
  if v_player.blackout_claimed_at is null then raise exception 'No blackout claim'; end if;

  select * into v_claim
  from blackout_claims
  where player_id=p_player_id
  for update;

  if not found then raise exception 'Blackout claim record not found'; end if;
  if v_claim.status <> 'pending' then raise exception 'Blackout claim has already been reviewed'; end if;

  if p_approved then
    update blackout_claims
    set status='approved', verified_at=v_now, note=p_note
    where id=v_claim.id;

    update players
    set blackout_status='approved',
        blackout_verified_at=v_now,
        blackout_note=p_note
    where id=p_player_id;

    insert into game_events(game_id,player_id,event_type,created_at,metadata)
    values(
      v_player.game_id,p_player_id,'blackout_verified',v_now,
      jsonb_build_object('approved',true,'note',p_note,'claim_id',v_claim.id)
    );
  else
    update blackout_claims
    set status='rejected', verified_at=v_now, note=p_note
    where id=v_claim.id;

    update players
    set blackout_status='rejected',
        blackout_note=p_note
    where id=p_player_id;

    insert into game_events(game_id,player_id,event_type,created_at,metadata)
    values(
      v_player.game_id,p_player_id,'blackout_rejected',v_now,
      jsonb_build_object('approved',false,'note',p_note,'claim_id',v_claim.id)
    );
  end if;

  return jsonb_build_object(
    'player_id',p_player_id,
    'status',(select blackout_status from players where id=p_player_id),
    'claim_id',v_claim.id
  );
end;
$$;

-- Prevent direct execution of the security-definer functions by anonymous users.
revoke execute on function public.join_game(text) from public, anon;
grant execute on function public.join_game(text) to authenticated;

revoke execute on function public.record_photo(uuid,int,text) from public, anon;
grant execute on function public.record_photo(uuid,int,text) to authenticated;

revoke execute on function public.admin_set_game_status(uuid,text) from public, anon;
grant execute on function public.admin_set_game_status(uuid,text) to authenticated;

revoke execute on function public.admin_verify_blackout(uuid,boolean,text) from public, anon;
grant execute on function public.admin_verify_blackout(uuid,boolean,text) to authenticated;

-- Keep the live game in realtime for admin dashboards and future public displays.
do $$
begin
  begin alter publication supabase_realtime add table public.players; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.player_squares; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.game_events; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.blackout_claims; exception when duplicate_object then null; end;
end $$;
