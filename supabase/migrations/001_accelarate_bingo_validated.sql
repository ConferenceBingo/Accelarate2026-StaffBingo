-- ACCELARATE 2026 Multiplayer Bingo — CLEAN MIGRATION
-- Run this entire file in the Supabase SQL Editor.
-- This migration preserves the five supplied cards and implements:
--   * SETUP / OPEN / PAUSED / CLOSED game states
--   * automatic Free Space
--   * Bingo = at least one complete ROW AND one complete COLUMN
--   * Blackout = all 24 attendee squares completed
--   * server-side timestamps
--   * auditable Blackout claims + organizer verification
--   * player/admin RLS and secure selfie storage
--   * idempotent policies and seed data

create extension if not exists pgcrypto;

-- ============================================================
-- 1. Core tables
-- ============================================================

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  status text not null default 'setup',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.games drop constraint if exists games_status_check;
alter table public.games
  add constraint games_status_check
  check (status in ('setup','open','paused','closed'));

insert into public.games (slug, title, status)
values ('accelarate-2026', 'ACCELARATE 2026 Networking Bingo', 'setup')
on conflict (slug) do nothing;

create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  card_number int not null,
  created_at timestamptz not null default now(),
  unique (game_id, card_number)
);

create table if not exists public.card_squares (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  square_index int not null check (square_index between 0 and 24),
  attendee_name text,
  organization text,
  is_free boolean not null default false,
  unique (card_id, square_index)
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
  blackout_status text not null default 'none'
    check (blackout_status in ('none','pending','approved','rejected')),
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
  unique (player_id, square_index)
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

create table if not exists public.blackout_claims (
  id bigint generated always as identity primary key,
  game_id uuid not null references public.games(id) on delete cascade,
  player_id uuid not null unique references public.players(id) on delete cascade,
  claimed_at timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  verified_at timestamptz,
  note text
);

create index if not exists idx_players_game
  on public.players(game_id);
create index if not exists idx_players_card
  on public.players(card_id);
create index if not exists idx_player_squares_player
  on public.player_squares(player_id);
create index if not exists idx_events_game_created
  on public.game_events(game_id, created_at);
create index if not exists idx_blackout_claims_game_time
  on public.blackout_claims(game_id, claimed_at, id);

-- Keep games.updated_at current.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists trg_games_updated_at on public.games;
create trigger trg_games_updated_at
before update on public.games
for each row
execute function public.touch_updated_at();

-- ============================================================
-- 2. Seed the five supplied cards
-- ============================================================

create temporary table if not exists tmp_acc_seed (
  card_number int not null,
  square_index int not null,
  attendee_name text,
  organization text not null,
  is_free boolean not null,
  primary key (card_number, square_index)
) on commit preserve rows;

truncate table tmp_acc_seed;

insert into tmp_acc_seed(card_number, square_index, attendee_name, organization, is_free) values
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
;

-- Validate the supplied card data before loading it.
do $$
declare
  v_card_count int;
  v_square_count int;
  v_free_count int;
begin
  select count(distinct card_number), count(*), count(*) filter (where is_free)
    into v_card_count, v_square_count, v_free_count
  from tmp_acc_seed;

  if v_card_count <> 5 then
    raise exception 'Seed validation failed: expected 5 cards, found %', v_card_count;
  end if;

  if v_square_count <> 125 then
    raise exception 'Seed validation failed: expected 125 squares, found %', v_square_count;
  end if;

  if v_free_count <> 5 then
    raise exception 'Seed validation failed: expected 5 Free Spaces, found %', v_free_count;
  end if;

  if exists (
    select 1
    from tmp_acc_seed
    group by card_number
    having count(*) <> 25
  ) then
    raise exception 'Seed validation failed: every card must have exactly 25 squares';
  end if;

  if exists (
    select 1
    from tmp_acc_seed
    group by card_number
    having count(*) filter (where square_index = 12 and is_free) <> 1
  ) then
    raise exception 'Seed validation failed: every card must have a Free Space at index 12';
  end if;
end;
$$;

insert into public.cards (game_id, card_number)
select g.id, s.card_number
from public.games g
cross join (select distinct card_number from tmp_acc_seed) s
where g.slug = 'accelarate-2026'
on conflict (game_id, card_number) do nothing;

insert into public.card_squares (
  card_id, square_index, attendee_name, organization, is_free
)
select
  c.id,
  s.square_index,
  s.attendee_name,
  s.organization,
  s.is_free
from public.cards c
join public.games g on g.id = c.game_id
join tmp_acc_seed s on s.card_number = c.card_number
where g.slug = 'accelarate-2026'
on conflict (card_id, square_index) do update
set
  attendee_name = excluded.attendee_name,
  organization = excluded.organization,
  is_free = excluded.is_free;

-- ============================================================
-- 3. Selfie storage
-- ============================================================

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'selfies',
  'selfies',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp','image/heic']::text[]
)
on conflict (id) do update
set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types =
    array['image/jpeg','image/png','image/webp','image/heic']::text[];

-- ============================================================
-- 4. Row-level security
-- ============================================================

alter table public.games enable row level security;
alter table public.cards enable row level security;
alter table public.card_squares enable row level security;
alter table public.players enable row level security;
alter table public.player_squares enable row level security;
alter table public.game_events enable row level security;
alter table public.admin_users enable row level security;
alter table public.blackout_claims enable row level security;

-- Drop policies first so this migration can safely be rerun.
drop policy if exists "game readable" on public.games;
drop policy if exists "card definitions readable" on public.cards;
drop policy if exists "square definitions readable" on public.card_squares;
drop policy if exists "player sees own player row" on public.players;
drop policy if exists "player sees own squares" on public.player_squares;
drop policy if exists "admins read players" on public.players;
drop policy if exists "admins read player squares" on public.player_squares;
drop policy if exists "admins read events" on public.game_events;
drop policy if exists "admins read admins" on public.admin_users;
drop policy if exists "admins read blackout claims" on public.blackout_claims;
drop policy if exists "player reads own blackout claim" on public.blackout_claims;

create policy "game readable"
on public.games
for select to authenticated
using (true);

create policy "card definitions readable"
on public.cards
for select to authenticated
using (true);

create policy "square definitions readable"
on public.card_squares
for select to authenticated
using (true);

create policy "player sees own player row"
on public.players
for select to authenticated
using (auth_user_id = auth.uid());

create policy "player sees own squares"
on public.player_squares
for select to authenticated
using (
  player_id in (
    select id
    from public.players
    where auth_user_id = auth.uid()
  )
);

create policy "admins read players"
on public.players
for select to authenticated
using (
  exists (
    select 1 from public.admin_users a
    where a.user_id = auth.uid()
  )
);

create policy "admins read player squares"
on public.player_squares
for select to authenticated
using (
  exists (
    select 1 from public.admin_users a
    where a.user_id = auth.uid()
  )
);

create policy "admins read events"
on public.game_events
for select to authenticated
using (
  exists (
    select 1 from public.admin_users a
    where a.user_id = auth.uid()
  )
);

create policy "admins read admins"
on public.admin_users
for select to authenticated
using (user_id = auth.uid());

create policy "admins read blackout claims"
on public.blackout_claims
for select to authenticated
using (
  exists (
    select 1 from public.admin_users a
    where a.user_id = auth.uid()
  )
);

create policy "player reads own blackout claim"
on public.blackout_claims
for select to authenticated
using (
  player_id in (
    select id
    from public.players
    where auth_user_id = auth.uid()
  )
);

-- Storage policies.
drop policy if exists "player uploads own selfies" on storage.objects;
drop policy if exists "player reads own selfies" on storage.objects;
drop policy if exists "player deletes own selfies" on storage.objects;
drop policy if exists "admins read selfies" on storage.objects;

create policy "player uploads own selfies"
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'selfies'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "player reads own selfies"
on storage.objects
for select to authenticated
using (
  bucket_id = 'selfies'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "player deletes own selfies"
on storage.objects
for delete to authenticated
using (
  bucket_id = 'selfies'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "admins read selfies"
on storage.objects
for select to authenticated
using (
  bucket_id = 'selfies'
  and exists (
    select 1 from public.admin_users a
    where a.user_id = auth.uid()
  )
);

-- ============================================================
-- 5. Player join
-- ============================================================

create or replace function public.join_game(p_player_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game public.games;
  v_player public.players;
  v_card public.cards;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_name := trim(coalesce(p_player_name, ''));

  if char_length(v_name) < 1 or char_length(v_name) > 80 then
    raise exception 'Player name must be between 1 and 80 characters';
  end if;

  select *
    into v_game
  from public.games
  where slug = 'accelarate-2026'
  for update;

  if not found then
    raise exception 'Game not configured';
  end if;

  if v_game.status <> 'open' then
    raise exception 'Game is not open';
  end if;

  select *
    into v_player
  from public.players
  where auth_user_id = auth.uid()
    and game_id = v_game.id;

  if found then
    return jsonb_build_object(
      'player_id', v_player.id,
      'card_number', (
        select card_number
        from public.cards
        where id = v_player.card_id
      ),
      'display_name', v_player.display_name
    );
  end if;

  select c.*
    into v_card
  from public.cards c
  left join public.players p
    on p.card_id = c.id
   and p.game_id = v_game.id
  where c.game_id = v_game.id
  group by c.id
  order by count(p.id), random()
  limit 1;

  if not found then
    raise exception 'No cards are configured';
  end if;

  insert into public.players (
    game_id, auth_user_id, display_name, card_id
  )
  values (
    v_game.id, auth.uid(), v_name, v_card.id
  )
  returning * into v_player;

  insert into public.player_squares (
    player_id, square_index, is_free, completed, completed_at
  )
  select
    v_player.id,
    s.square_index,
    s.is_free,
    s.is_free,
    case when s.is_free then clock_timestamp() else null end
  from public.card_squares s
  where s.card_id = v_card.id;

  insert into public.game_events (
    game_id, player_id, event_type, metadata
  )
  values (
    v_game.id,
    v_player.id,
    'player_joined',
    jsonb_build_object('card_number', v_card.card_number)
  );

  return jsonb_build_object(
    'player_id', v_player.id,
    'card_number', v_card.card_number,
    'display_name', v_player.display_name
  );
end;
$$;

-- ============================================================
-- 6. Record selfie + Bingo + Blackout
-- ============================================================

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
  v_player public.players;
  v_game public.games;
  v_now timestamptz := clock_timestamp();

  v_row_complete boolean := false;
  v_col_complete boolean := false;
  v_bingo boolean := false;

  v_row int := null;
  v_col int := null;
  v_pattern text := null;

  v_bingo_at timestamptz := null;
  v_blackout_at timestamptz := null;

  v_all_complete boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_square_index is null
     or p_square_index < 0
     or p_square_index > 24 then
    raise exception 'Invalid square';
  end if;

  if p_square_index = 12 then
    raise exception 'Free Space is automatic';
  end if;

  if p_photo_path is null
     or char_length(trim(p_photo_path)) = 0 then
    raise exception 'Photo path is required';
  end if;

  -- The first folder in the storage path must be the authenticated
  -- user's auth ID.
  if (storage.foldername(p_photo_path))[1] <> auth.uid()::text then
    raise exception 'Photo path does not belong to the authenticated user';
  end if;

  select *
    into v_player
  from public.players
  where id = p_player_id
    and auth_user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Player session not found';
  end if;

  select *
    into v_game
  from public.games
  where id = v_player.game_id;

  if v_game.status <> 'open' then
    raise exception 'Game is not open';
  end if;

  if not exists (
    select 1
    from public.card_squares
    where card_id = v_player.card_id
      and square_index = p_square_index
      and not is_free
  ) then
    raise exception 'Invalid card square';
  end if;

  update public.player_squares
  set
    completed = true,
    photo_path = p_photo_path,
    completed_at = coalesce(completed_at, v_now)
  where player_id = v_player.id
    and square_index = p_square_index
    and not completed;

  for v_row in 0..4 loop
    if not exists (
      select 1
      from generate_series(0,4) as c
      where not exists (
        select 1
        from public.player_squares ps
        where ps.player_id = v_player.id
          and ps.square_index = v_row * 5 + c
          and ps.completed
      )
    ) then
      v_row_complete := true;
      exit;
    end if;
  end loop;

  -- Find a complete column independently of the row check.
  for v_col in 0..4 loop
    if not exists (
      select 1
      from generate_series(0,4) as r
      where not exists (
        select 1
        from public.player_squares ps
        where ps.player_id = v_player.id
          and ps.square_index = r * 5 + v_col
          and ps.completed
      )
    ) then
      v_col_complete := true;
      exit;
    end if;
  end loop;

  -- Final Bingo rule: BOTH a complete row AND a complete column.
  if v_row_complete and v_col_complete then
    v_bingo := true;
    v_pattern :=
      'Row ' || (v_row + 1) || ' + Column ' || chr(65 + v_col);
  end if;

  if v_bingo and v_player.first_bingo_at is null then
    update public.players
    set
      first_bingo_at = v_now,
      first_bingo_pattern = v_pattern
    where id = v_player.id;

    insert into public.game_events (
      game_id, player_id, event_type, pattern, created_at
    )
    values (
      v_player.game_id,
      v_player.id,
      'bingo',
      v_pattern,
      v_now
    );

    v_bingo_at := v_now;
  end if;

  -- Blackout requires every attendee square to be complete.
  select not exists (
    select 1
    from public.player_squares
    where player_id = v_player.id
      and is_free = false
      and completed = false
  )
  into v_all_complete;

  if v_all_complete and v_player.blackout_claimed_at is null then
    update public.players
    set
      blackout_claimed_at = v_now,
      blackout_status = 'pending'
    where id = v_player.id;

    insert into public.blackout_claims (
      game_id, player_id, claimed_at, status
    )
    values (
      v_player.game_id, v_player.id, v_now, 'pending'
    )
    on conflict (player_id) do nothing;

    insert into public.game_events (
      game_id, player_id, event_type, created_at
    )
    values (
      v_player.game_id,
      v_player.id,
      'blackout_claimed',
      v_now
    );

    v_blackout_at := v_now;
  end if;

  return jsonb_build_object(
    'player_id', v_player.id,
    'square_index', p_square_index,
    'completed_at', v_now,
    'bingo_achieved', v_bingo_at is not null,
    'bingo_at', v_bingo_at,
    'bingo_pattern', case
      when v_bingo_at is not null then v_pattern
      else null
    end,
    'blackout_achieved', v_blackout_at is not null,
    'blackout_at', v_blackout_at,
    'completed_count', (
      select count(*)
      from public.player_squares
      where player_id = v_player.id
        and completed
        and not is_free
    ),
    'full_count', (
      select count(*)
      from public.player_squares
      where player_id = v_player.id
        and not is_free
    )
  );
end;
$$;

-- ============================================================
-- 7. Organizer game-state control
-- ============================================================

create or replace function public.admin_set_game_status(
  p_game_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game public.games;
begin
  if not exists (
    select 1
    from public.admin_users
    where user_id = auth.uid()
  ) then
    raise exception 'Admin access required';
  end if;

  if p_status not in ('setup','open','paused','closed') then
    raise exception 'Invalid game status';
  end if;

  update public.games
  set status = p_status
  where id = p_game_id
  returning * into v_game;

  if not found then
    raise exception 'Game not found';
  end if;

  insert into public.game_events (
    game_id, event_type, created_at, metadata
  )
  values (
    p_game_id,
    'game_status_changed',
    clock_timestamp(),
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object(
    'game_id', v_game.id,
    'status', v_game.status,
    'updated_at', v_game.updated_at
  );
end;
$$;

-- ============================================================
-- 8. Organizer Blackout verification
-- ============================================================

create or replace function public.admin_verify_blackout(
  p_player_id uuid,
  p_approved boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players;
  v_claim public.blackout_claims;
  v_now timestamptz := clock_timestamp();
begin
  if not exists (
    select 1
    from public.admin_users
    where user_id = auth.uid()
  ) then
    raise exception 'Admin access required';
  end if;

  select *
    into v_player
  from public.players
  where id = p_player_id
  for update;

  if not found then
    raise exception 'Player not found';
  end if;

  select *
    into v_claim
  from public.blackout_claims
  where player_id = p_player_id
  for update;

  if not found then
    raise exception 'No blackout claim';
  end if;

  if v_claim.status <> 'pending' then
    raise exception 'Blackout claim has already been reviewed';
  end if;

  -- Do not allow a later claim to be approved while an earlier
  -- pending/approved claim for the same game remains unresolved.
  if p_approved and exists (
    select 1
    from public.blackout_claims earlier
    where earlier.game_id = v_claim.game_id
      and earlier.claimed_at < v_claim.claimed_at
      and earlier.status in ('pending','approved')
  ) then
    raise exception 'An earlier Blackout claim must be resolved first';
  end if;

  if p_approved then
    update public.blackout_claims
    set
      status = 'approved',
      verified_at = v_now,
      note = p_note
    where id = v_claim.id;

    update public.players
    set
      blackout_status = 'approved',
      blackout_verified_at = v_now,
      blackout_note = p_note
    where id = p_player_id;

    insert into public.game_events (
      game_id, player_id, event_type, created_at, metadata
    )
    values (
      v_player.game_id,
      p_player_id,
      'blackout_verified',
      v_now,
      jsonb_build_object(
        'approved', true,
        'note', p_note
      )
    );
  else
    update public.blackout_claims
    set
      status = 'rejected',
      verified_at = v_now,
      note = p_note
    where id = v_claim.id;

    update public.players
    set
      blackout_status = 'rejected',
      blackout_note = p_note
    where id = p_player_id;

    insert into public.game_events (
      game_id, player_id, event_type, created_at, metadata
    )
    values (
      v_player.game_id,
      p_player_id,
      'blackout_rejected',
      v_now,
      jsonb_build_object(
        'approved', false,
        'note', p_note
      )
    );
  end if;

  return jsonb_build_object(
    'player_id', p_player_id,
    'claim_id', v_claim.id,
    'status', (
      select status
      from public.blackout_claims
      where id = v_claim.id
    )
  );
end;
$$;

-- ============================================================
-- 9. Permissions
-- ============================================================

revoke all on function public.join_game(text) from public;
grant execute on function public.join_game(text) to authenticated;

revoke all on function public.record_photo(uuid, int, text) from public;
grant execute on function public.record_photo(uuid, int, text) to authenticated;

revoke all on function public.admin_set_game_status(uuid, text) from public;
grant execute on function public.admin_set_game_status(uuid, text) to authenticated;

revoke all on function public.admin_verify_blackout(uuid, boolean, text) from public;
grant execute on function public.admin_verify_blackout(uuid, boolean, text) to authenticated;

grant select on public.games to authenticated;
grant select on public.cards to authenticated;
grant select on public.card_squares to authenticated;
grant select on public.players to authenticated;
grant select on public.player_squares to authenticated;
grant select on public.game_events to authenticated;
grant select on public.admin_users to authenticated;
grant select on public.blackout_claims to authenticated;

-- ============================================================
-- 10. Realtime
-- ============================================================

do $$
begin
  begin
    alter publication supabase_realtime add table public.players;
  exception
    when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.player_squares;
  exception
    when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.game_events;
  exception
    when duplicate_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.blackout_claims;
  exception
    when duplicate_object then null;
  end;
end;
$$;

-- ============================================================
-- End of migration
-- ============================================================
