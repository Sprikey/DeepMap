-- DeepMap — materializar o conteúdo adicional submetido pela comunidade
-- Executar depois de map-community-contributions.sql.

begin;

create or replace function private.deepmap_materialize_submission_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_item jsonb;
    v_type text;
    v_text_en text;
    v_text_pt text;
    v_section_id bigint;
    v_sort integer := 0;
begin
    if old.status = 'pending'
       and new.status = 'approved'
       and new.submission_type = 'create'
       and new.marker_id is not null
       and jsonb_typeof(new.payload->'content_items') = 'array' then

        for v_item in
            select value
              from jsonb_array_elements(new.payload->'content_items')
        loop
            v_type := coalesce(nullif(btrim(v_item->>'type'), ''), 'note');
            if v_type not in ('npc', 'item', 'reward', 'requirement', 'note') then
                v_type := 'note';
            end if;

            v_text_en := nullif(btrim(v_item->>'text_en'), '');
            v_text_pt := nullif(btrim(v_item->>'text_pt'), '');

            if v_text_en is null and v_text_pt is null then
                continue;
            end if;

            v_sort := v_sort + 10;

            insert into public.marker_sections (
                marker_id,
                section_type,
                title_en,
                title_pt,
                sort_order,
                is_collapsible,
                metadata
            ) values (
                new.marker_id,
                v_type,
                case v_type
                    when 'npc' then 'NPC'
                    when 'item' then 'Item'
                    when 'reward' then 'Reward'
                    when 'requirement' then 'Requirement'
                    else 'Note'
                end,
                case v_type
                    when 'npc' then 'NPC'
                    when 'item' then 'Item'
                    when 'reward' then 'Recompensa'
                    when 'requirement' then 'Requisito'
                    else 'Nota'
                end,
                v_sort,
                true,
                jsonb_build_object('editor', 'quick-content-v1', 'source', 'community-submission')
            )
            returning id into v_section_id;

            insert into public.marker_section_rows (
                section_id,
                row_type,
                text_en,
                text_pt,
                sort_order,
                metadata
            ) values (
                v_section_id,
                'text',
                v_text_en,
                v_text_pt,
                10,
                jsonb_build_object('editor', 'quick-content-v1', 'source', 'community-submission')
            );
        end loop;
    end if;

    return new;
end;
$$;

drop trigger if exists deepmap_materialize_submission_content
on public.marker_submissions;

create trigger deepmap_materialize_submission_content
after update of status
on public.marker_submissions
for each row
when (old.status is distinct from new.status)
execute function private.deepmap_materialize_submission_content();

commit;
