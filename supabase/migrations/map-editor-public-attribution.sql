-- DeepMap Map Editor 2.0 — public publisher attribution
-- Exposes only the current public @username of the account that published a marker.
-- Moderator/editor audit details remain private/admin-only.

begin;

create or replace function public.get_public_marker_attribution(p_game_id text)
returns table (
    marker_id bigint,
    published_username text
)
language sql
stable
security definer
set search_path = ''
as $$
    select
        a.marker_id,
        p.username as published_username
    from private.marker_editor_audit as a
    join public.marcadores as m
      on m.id = a.marker_id
    left join public.profiles as p
      on p.id = a.published_by
    where m.game_id = p_game_id
      and m.is_published = true
      and a.published_by is not null;
$$;

revoke all on function public.get_public_marker_attribution(text)
from public, anon, authenticated;

grant execute on function public.get_public_marker_attribution(text)
to anon, authenticated;

commit;
