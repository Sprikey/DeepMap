-- Map Editor Schema
-- Base flexível e autónoma do Map Editor 2.0.
--
-- Esta query pode ser executada mesmo quando public.marcadores ainda não existe.
-- Cria:
--   - administração privada;
--   - layers do mapa;
--   - grupos e categorias configuráveis;
--   - marcadores;
--   - múltiplas imagens;
--   - secções e linhas flexíveis de conteúdo;
--   - RLS e permissões.
--
-- Não cria armas/arma_upgrades. Essas tabelas ficam para uma fase própria,
-- quando o catálogo de equipamento for desenhado.

begin;

create schema if not exists private;


-- =========================================================
-- 1. ADMINISTRAÇÃO
-- =========================================================

create table if not exists private.deepmap_admins (
    user_id uuid primary key
        references auth.users(id)
        on delete cascade,

    created_at timestamptz not null default now()
);

alter table private.deepmap_admins enable row level security;

revoke all on table private.deepmap_admins
from public, anon, authenticated;

create or replace function private.is_deepmap_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from private.deepmap_admins as a
        where a.user_id = (select auth.uid())
    );
$$;

revoke all on function private.is_deepmap_admin()
from public, anon, authenticated;

grant usage on schema private to anon, authenticated;
grant execute on function private.is_deepmap_admin() to authenticated;


-- =========================================================
-- 2. LAYERS DO MAPA
-- =========================================================

create table if not exists public.map_layers (
    game_id text not null,
    id text not null,

    name_en text not null,
    name_pt text not null,

    image_source text not null default 'none'
        check (image_source in ('none', 'static', 'r2', 'external')),

    image_ref text,

    width integer not null default 8000
        check (width > 0),

    height integer not null default 8000
        check (height > 0),

    sort_order integer not null default 0,
    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    primary key (game_id, id),

    constraint map_layers_id_format
        check (id ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'),

    constraint map_layers_image_ref_required
        check (
            image_source = 'none'
            or nullif(btrim(image_ref), '') is not null
        )
);

insert into public.map_layers (
    game_id, id, name_en, name_pt,
    image_source, image_ref,
    width, height, sort_order, is_active
)
values
    (
        'elden-ring', 'surface', 'Surface', 'Superfície',
        'static', '/games/elden-ring/maps/surface.jpg',
        8000, 8000, 10, true
    ),
    (
        'elden-ring', 'underground', 'Underground', 'Subterrâneo',
        'none', null,
        8000, 8000, 20, true
    ),
    (
        'elden-ring', 'dlc', 'DLC', 'DLC',
        'none', null,
        8000, 8000, 30, true
    )
on conflict (game_id, id) do nothing;


-- =========================================================
-- 3. GRUPOS DE CATEGORIAS
-- =========================================================

create table if not exists public.marker_category_groups (
    game_id text not null,
    id text not null,

    name_en text not null,
    name_pt text not null,

    sort_order integer not null default 0,
    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    primary key (game_id, id),

    constraint marker_category_groups_id_format
        check (id ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$')
);

insert into public.marker_category_groups (
    game_id, id, name_en, name_pt, sort_order, is_active
)
values
    ('elden-ring', 'locations', 'Locations', 'Locais', 10, true),
    ('elden-ring', 'collectibles', 'Collectibles', 'Colecionáveis', 20, true)
on conflict (game_id, id) do nothing;


-- =========================================================
-- 4. CATEGORIAS DE MARCADORES
-- =========================================================

create table if not exists public.marker_categories (
    game_id text not null,
    id text not null,

    group_id text,

    name_en text not null,
    name_pt text not null,

    icon_source text not null default 'none'
        check (icon_source in ('none', 'static', 'r2', 'external')),

    icon_ref text,

    color text not null default '#777777'
        check (color ~ '^#[0-9A-Fa-f]{6}$'),

    marker_width integer
        check (marker_width is null or marker_width > 0),

    marker_height integer
        check (marker_height is null or marker_height > 0),

    symbol_size integer
        check (symbol_size is null or symbol_size > 0),

    sort_order integer not null default 0,
    is_active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    primary key (game_id, id),

    constraint marker_categories_id_format
        check (id ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'),

    constraint marker_categories_icon_ref_required
        check (
            icon_source = 'none'
            or nullif(btrim(icon_ref), '') is not null
        ),

    constraint marker_categories_group_fk
        foreign key (game_id, group_id)
        references public.marker_category_groups (game_id, id)
        on update cascade
        on delete set null
);

insert into public.marker_categories (
    game_id, id, group_id,
    name_en, name_pt,
    icon_source, icon_ref, color,
    marker_width, marker_height, symbol_size,
    sort_order, is_active
)
values
    (
        'elden-ring', 'site_of_grace', 'locations',
        'Sites of Grace', 'Locais de Graça',
        'static', '/games/elden-ring/icons/site-of-grace.png', '#23233a',
        30, 39, 22,
        10, true
    ),
    (
        'elden-ring', 'dungeon', 'locations',
        'Dungeons & Caverns', 'Masmorras e Cavernas',
        'none', null, '#7b6b91',
        null, null, null,
        20, true
    ),
    (
        'elden-ring', 'boss', 'locations',
        'Bosses', 'Chefes',
        'none', null, '#8f4f4f',
        null, null, null,
        30, true
    ),
    (
        'elden-ring', 'weapon_equipment', 'collectibles',
        'Weapons & Equipment', 'Armas e Equipamento',
        'none', null, '#557a8f',
        null, null, null,
        40, true
    ),
    (
        'elden-ring', 'stonesword_key', 'collectibles',
        'Stonesword Keys', 'Chaves de Espada de Pedra',
        'none', null, '#777777',
        null, null, null,
        50, true
    ),
    (
        'elden-ring', 'talisman', 'collectibles',
        'Talismans', 'Talismãs',
        'none', null, '#8b7545',
        null, null, null,
        60, true
    )
on conflict (game_id, id) do nothing;


-- =========================================================
-- 5. MARCADORES
-- =========================================================

create table if not exists public.marcadores (
    id bigint generated by default as identity primary key,

    game_id text not null default 'elden-ring',
    map_layer text not null default 'surface',

    slug text not null,

    category_id text not null,
    region_id text,

    title_en text not null,
    title_pt text not null,

    coordinate_x double precision not null,
    coordinate_y double precision not null,

    description_en text,
    description_pt text,

    video_url text,

    -- Override visual por marcador.
    -- NULL = herda da categoria.
    color_override text,
    icon_source_override text,
    icon_ref_override text,
    marker_width_override integer,
    marker_height_override integer,
    symbol_size_override integer,

    is_published boolean not null default false,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint marcadores_slug_format
        check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),

    constraint marcadores_color_override_format
        check (
            color_override is null
            or color_override ~ '^#[0-9A-Fa-f]{6}$'
        ),

    constraint marcadores_icon_source_override_valid
        check (
            icon_source_override is null
            or icon_source_override in ('none', 'static', 'r2', 'external')
        ),

    constraint marcadores_icon_override_ref_required
        check (
            icon_source_override is null
            or icon_source_override = 'none'
            or nullif(btrim(icon_ref_override), '') is not null
        ),

    constraint marcadores_marker_width_override_valid
        check (
            marker_width_override is null
            or marker_width_override > 0
        ),

    constraint marcadores_marker_height_override_valid
        check (
            marker_height_override is null
            or marker_height_override > 0
        ),

    constraint marcadores_symbol_size_override_valid
        check (
            symbol_size_override is null
            or symbol_size_override > 0
        ),

    constraint marcadores_layer_fk
        foreign key (game_id, map_layer)
        references public.map_layers (game_id, id)
        on update cascade,

    constraint marcadores_category_fk
        foreign key (game_id, category_id)
        references public.marker_categories (game_id, id)
        on update cascade
);

create unique index if not exists marcadores_game_slug_unique
    on public.marcadores (game_id, slug);

create index if not exists marcadores_map_lookup_idx
    on public.marcadores (
        game_id,
        map_layer,
        is_published,
        category_id
    );


-- =========================================================
-- 6. MÚLTIPLAS IMAGENS POR MARCADOR
-- =========================================================

create table if not exists public.marker_images (
    id bigint generated by default as identity primary key,

    marker_id bigint not null
        references public.marcadores(id)
        on delete cascade,

    source text not null default 'r2'
        check (source in ('static', 'r2', 'external')),

    image_ref text not null,

    alt_en text,
    alt_pt text,

    caption_en text,
    caption_pt text,

    sort_order integer not null default 0,
    is_cover boolean not null default false,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint marker_images_ref_not_empty
        check (nullif(btrim(image_ref), '') is not null)
);

create index if not exists marker_images_marker_sort_idx
    on public.marker_images (marker_id, sort_order, id);

create unique index if not exists marker_images_one_cover_per_marker
    on public.marker_images (marker_id)
    where is_cover = true;


-- =========================================================
-- 7. SECÇÕES FLEXÍVEIS
-- =========================================================
-- Exemplos:
-- NPC: Merchant Kalé
--   -> Dialogue
--   -> Items for sale
--
-- section_type é deliberadamente aberto:
-- npc, dialogue, items, notes, quest, custom, etc.

create table if not exists public.marker_sections (
    id bigint generated by default as identity primary key,

    marker_id bigint not null
        references public.marcadores(id)
        on delete cascade,

    parent_section_id bigint,

    section_type text not null default 'custom',

    title_en text,
    title_pt text,

    sort_order integer not null default 0,
    is_collapsible boolean not null default true,

    metadata jsonb not null default '{}'::jsonb,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint marker_sections_type_format
        check (section_type ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'),

    constraint marker_sections_id_marker_unique
        unique (id, marker_id),

    constraint marker_sections_parent_same_marker_fk
        foreign key (parent_section_id, marker_id)
        references public.marker_sections (id, marker_id)
        on delete cascade
);

create index if not exists marker_sections_marker_sort_idx
    on public.marker_sections (
        marker_id,
        parent_section_id,
        sort_order,
        id
    );


-- =========================================================
-- 8. LINHAS DAS SECÇÕES
-- =========================================================
-- Uma linha pode representar diálogo, item, preço, nota, requisito, etc.

create table if not exists public.marker_section_rows (
    id bigint generated by default as identity primary key,

    section_id bigint not null
        references public.marker_sections(id)
        on delete cascade,

    row_type text not null default 'text',

    label_en text,
    label_pt text,

    text_en text,
    text_pt text,

    detail_en text,
    detail_pt text,

    value_en text,
    value_pt text,

    icon_source text
        check (
            icon_source is null
            or icon_source in ('none', 'static', 'r2', 'external')
        ),

    icon_ref text,

    image_source text
        check (
            image_source is null
            or image_source in ('static', 'r2', 'external')
        ),

    image_ref text,

    sort_order integer not null default 0,

    metadata jsonb not null default '{}'::jsonb,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint marker_section_rows_type_format
        check (row_type ~ '^[a-z0-9]+(?:[_-][a-z0-9]+)*$'),

    constraint marker_section_rows_icon_ref_required
        check (
            icon_source is null
            or icon_source = 'none'
            or nullif(btrim(icon_ref), '') is not null
        ),

    constraint marker_section_rows_image_ref_required
        check (
            image_source is null
            or nullif(btrim(image_ref), '') is not null
        )
);

create index if not exists marker_section_rows_section_sort_idx
    on public.marker_section_rows (section_id, sort_order, id);


-- =========================================================
-- 9. UPDATED_AT AUTOMÁTICO
-- =========================================================

create or replace function private.deepmap_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

revoke all on function private.deepmap_touch_updated_at()
from public, anon, authenticated;

drop trigger if exists deepmap_marcadores_touch_updated_at
on public.marcadores;

create trigger deepmap_marcadores_touch_updated_at
before update on public.marcadores
for each row
execute function private.deepmap_touch_updated_at();

drop trigger if exists deepmap_map_layers_touch_updated_at
on public.map_layers;

create trigger deepmap_map_layers_touch_updated_at
before update on public.map_layers
for each row
execute function private.deepmap_touch_updated_at();

drop trigger if exists deepmap_category_groups_touch_updated_at
on public.marker_category_groups;

create trigger deepmap_category_groups_touch_updated_at
before update on public.marker_category_groups
for each row
execute function private.deepmap_touch_updated_at();

drop trigger if exists deepmap_marker_categories_touch_updated_at
on public.marker_categories;

create trigger deepmap_marker_categories_touch_updated_at
before update on public.marker_categories
for each row
execute function private.deepmap_touch_updated_at();

drop trigger if exists deepmap_marker_images_touch_updated_at
on public.marker_images;

create trigger deepmap_marker_images_touch_updated_at
before update on public.marker_images
for each row
execute function private.deepmap_touch_updated_at();

drop trigger if exists deepmap_marker_sections_touch_updated_at
on public.marker_sections;

create trigger deepmap_marker_sections_touch_updated_at
before update on public.marker_sections
for each row
execute function private.deepmap_touch_updated_at();

drop trigger if exists deepmap_marker_section_rows_touch_updated_at
on public.marker_section_rows;

create trigger deepmap_marker_section_rows_touch_updated_at
before update on public.marker_section_rows
for each row
execute function private.deepmap_touch_updated_at();


-- =========================================================
-- 10. HELPERS DE LEITURA
-- =========================================================

create or replace function private.marker_is_public(p_marker_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.marcadores as m
        where m.id = p_marker_id
          and m.is_published = true
    );
$$;

revoke all on function private.marker_is_public(bigint)
from public, anon, authenticated;

grant execute on function private.marker_is_public(bigint)
to anon, authenticated;


create or replace function private.section_marker_id(p_section_id bigint)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select s.marker_id
    from public.marker_sections as s
    where s.id = p_section_id;
$$;

revoke all on function private.section_marker_id(bigint)
from public, anon, authenticated;

grant execute on function private.section_marker_id(bigint)
to anon, authenticated;


-- =========================================================
-- 11. RLS + PERMISSÕES
-- =========================================================

alter table public.map_layers enable row level security;
alter table public.marker_category_groups enable row level security;
alter table public.marker_categories enable row level security;
alter table public.marcadores enable row level security;
alter table public.marker_images enable row level security;
alter table public.marker_sections enable row level security;
alter table public.marker_section_rows enable row level security;

revoke all on table
    public.map_layers,
    public.marker_category_groups,
    public.marker_categories,
    public.marcadores,
    public.marker_images,
    public.marker_sections,
    public.marker_section_rows
from public, anon, authenticated;

grant select on table
    public.map_layers,
    public.marker_category_groups,
    public.marker_categories,
    public.marcadores,
    public.marker_images,
    public.marker_sections,
    public.marker_section_rows
to anon, authenticated;

grant insert, update, delete on table
    public.map_layers,
    public.marker_category_groups,
    public.marker_categories,
    public.marcadores,
    public.marker_images,
    public.marker_sections,
    public.marker_section_rows
to authenticated;

grant usage, select on sequence public.marcadores_id_seq
to authenticated;

grant usage, select on sequence public.marker_images_id_seq
to authenticated;

grant usage, select on sequence public.marker_sections_id_seq
to authenticated;

grant usage, select on sequence public.marker_section_rows_id_seq
to authenticated;


-- map_layers

drop policy if exists "map_layers_public_read"
on public.map_layers;

create policy "map_layers_public_read"
on public.map_layers
for select
to anon, authenticated
using (is_active = true);

drop policy if exists "map_layers_admin_all"
on public.map_layers;

create policy "map_layers_admin_all"
on public.map_layers
for all
to authenticated
using (private.is_deepmap_admin())
with check (private.is_deepmap_admin());


-- category groups

drop policy if exists "marker_category_groups_public_read"
on public.marker_category_groups;

create policy "marker_category_groups_public_read"
on public.marker_category_groups
for select
to anon, authenticated
using (is_active = true);

drop policy if exists "marker_category_groups_admin_all"
on public.marker_category_groups;

create policy "marker_category_groups_admin_all"
on public.marker_category_groups
for all
to authenticated
using (private.is_deepmap_admin())
with check (private.is_deepmap_admin());


-- categories

drop policy if exists "marker_categories_public_read"
on public.marker_categories;

create policy "marker_categories_public_read"
on public.marker_categories
for select
to anon, authenticated
using (is_active = true);

drop policy if exists "marker_categories_admin_all"
on public.marker_categories;

create policy "marker_categories_admin_all"
on public.marker_categories
for all
to authenticated
using (private.is_deepmap_admin())
with check (private.is_deepmap_admin());


-- markers

drop policy if exists "marcadores_public_read"
on public.marcadores;

create policy "marcadores_public_read"
on public.marcadores
for select
to anon, authenticated
using (is_published = true);

drop policy if exists "marcadores_admin_all"
on public.marcadores;

create policy "marcadores_admin_all"
on public.marcadores
for all
to authenticated
using (private.is_deepmap_admin())
with check (private.is_deepmap_admin());


-- marker images

drop policy if exists "marker_images_public_read"
on public.marker_images;

create policy "marker_images_public_read"
on public.marker_images
for select
to anon, authenticated
using (private.marker_is_public(marker_id));

drop policy if exists "marker_images_admin_all"
on public.marker_images;

create policy "marker_images_admin_all"
on public.marker_images
for all
to authenticated
using (private.is_deepmap_admin())
with check (private.is_deepmap_admin());


-- marker sections

drop policy if exists "marker_sections_public_read"
on public.marker_sections;

create policy "marker_sections_public_read"
on public.marker_sections
for select
to anon, authenticated
using (private.marker_is_public(marker_id));

drop policy if exists "marker_sections_admin_all"
on public.marker_sections;

create policy "marker_sections_admin_all"
on public.marker_sections
for all
to authenticated
using (private.is_deepmap_admin())
with check (private.is_deepmap_admin());


-- marker section rows

drop policy if exists "marker_section_rows_public_read"
on public.marker_section_rows;

create policy "marker_section_rows_public_read"
on public.marker_section_rows
for select
to anon, authenticated
using (
    private.marker_is_public(
        private.section_marker_id(section_id)
    )
);

drop policy if exists "marker_section_rows_admin_all"
on public.marker_section_rows;

create policy "marker_section_rows_admin_all"
on public.marker_section_rows
for all
to authenticated
using (private.is_deepmap_admin())
with check (private.is_deepmap_admin());


commit;


-- =========================================================
-- PASSO MANUAL DEPOIS DO SUCCESS
-- =========================================================
-- NÃO executar antes de a query principal terminar com sucesso.
--
-- insert into private.deepmap_admins (user_id)
-- values ('COLOCA-AQUI-O-TEU-UUID')
-- on conflict (user_id) do nothing;
