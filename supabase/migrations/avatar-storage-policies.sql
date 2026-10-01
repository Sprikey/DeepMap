-- v1.0.31 — 02 | Avatar Storage Policies
-- Políticas de acesso ao bucket avatars para ficheiros personalizados por utilizador.

-- DeepMap: avatares personalizados
-- Cada utilizador guarda as imagens na pasta com o seu UUID.
-- Exemplo: avatars/UUID/avatar-123.webp

-- 1. Consultar os próprios ficheiros
create policy "deepmap_avatars_select_own"
on storage.objects
for select
to authenticated
using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- 2. Carregar imagens apenas na própria pasta
create policy "deepmap_avatars_insert_own"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 1
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);

-- 3. Apagar apenas os próprios ficheiros
create policy "deepmap_avatars_delete_own"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and owner_id = (select auth.uid())::text
);
