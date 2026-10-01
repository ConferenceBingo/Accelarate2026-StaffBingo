-- ACCELARATE 2026 — Latest Bingo rules
-- BINGO requires BOTH at least one complete horizontal row AND
-- at least one complete vertical column.
-- BLACKOUT remains all 24 attendee squares + the automatic Free Space.

create or replace function public.record_photo(p_player_id uuid,p_square_index int,p_photo_path text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player players;
  v_game games;
  v_now timestamptz := clock_timestamp();
  v_has_row boolean := false;
  v_has_col boolean := false;
  v_bingo boolean := false;
  v_row_pattern text := null;
  v_col_pattern text := null;
  v_pattern text := null;
  v_blackout boolean := false;
  v_i int;
  v_all boolean;
  v_bingo_at timestamptz;
  v_blackout_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

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
  ) then raise exception 'Invalid card square'; end if;

  update player_squares
  set completed=true,
      photo_path=p_photo_path,
      completed_at=coalesce(completed_at,v_now)
  where player_id=v_player.id
    and square_index=p_square_index
    and not completed;

  -- BINGO requires BOTH a full horizontal row AND a full vertical column.
  -- The center Free Space is already marked completed for every player.
  for v_i in 0..4 loop
    if exists(
      select 1
      from generate_series(v_i*5, v_i*5+4) g(idx)
      where not exists(
        select 1 from player_squares ps
        where ps.player_id=v_player.id
          and ps.square_index=g.idx
          and ps.completed
      )
    ) then
      continue;
    end if;
    v_has_row := true;
    if v_row_pattern is null then
      v_row_pattern := 'Row ' || (v_i+1);
    end if;
  end loop;

  for v_i in 0..4 loop
    if exists(
      select 1
      from generate_series(0,4) r(row_num)
      where not exists(
        select 1 from player_squares ps
        where ps.player_id=v_player.id
          and ps.square_index=(r.row_num*5)+v_i
          and ps.completed
      )
    ) then
      continue;
    end if;
    v_has_col := true;
    if v_col_pattern is null then
      v_col_pattern := 'Column ' || chr(66+v_i);
    end if;
  end loop;

  v_bingo := v_has_row and v_has_col;
  if v_bingo then
    v_pattern := v_row_pattern || ' + ' || v_col_pattern;
  end if;

  if v_bingo and v_player.first_bingo_at is null then
    update players
    set first_bingo_at=v_now,
        first_bingo_pattern=v_pattern
    where id=v_player.id;

    insert into game_events(game_id,player_id,event_type,pattern,created_at,metadata)
    values(
      v_player.game_id,
      v_player.id,
      'bingo',
      v_pattern,
      v_now,
      jsonb_build_object(
        'requires_row_and_column',true,
        'row_pattern',v_row_pattern,
        'column_pattern',v_col_pattern
      )
    );
    v_bingo_at := v_now;
  end if;

  -- BLACKOUT remains 24 attendee squares completed; Free Space is automatic.
  select not exists(
    select 1 from player_squares
    where player_id=v_player.id and completed=false
  ) into v_all;

  if v_all and v_player.blackout_claimed_at is null then
    update players
    set blackout_claimed_at=v_now,
        blackout_status='pending'
    where id=v_player.id;

    insert into game_events(game_id,player_id,event_type,created_at,metadata)
    values(
      v_player.game_id,
      v_player.id,
      'blackout_claimed',
      v_now,
      jsonb_build_object('requires_full_board',true,'attendee_square_count',24)
    );
    v_blackout := true;
    v_blackout_at := v_now;
  end if;

  return jsonb_build_object(
    'player_id',v_player.id,
    'square_index',p_square_index,
    'completed_at',v_now,
    'row_completed',v_has_row,
    'column_completed',v_has_col,
    'bingo_achieved',v_bingo_at is not null,
    'bingo_at',v_bingo_at,
    'bingo_pattern',v_pattern,
    'bingo_rule','At least one complete row AND at least one complete column',
    'blackout_achieved',v_blackout,
    'blackout_at',v_blackout_at,
    'blackout_rule','All 24 attendee squares completed; Free Space is automatic',
    'completed_count',(select count(*) from player_squares where player_id=v_player.id and completed and not is_free),
    'full_count',(select count(*) from player_squares where player_id=v_player.id and not is_free)
  );
end;
$$;

-- Ensure clients can safely call the function through the authenticated API.
grant execute on function public.record_photo(uuid,int,text) to authenticated;
