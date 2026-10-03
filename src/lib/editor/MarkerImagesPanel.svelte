<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import {
        createMarkerImage,
        deleteMarkerImage,
        loadMarkerImages,
        moveMarkerImage,
        resolveMarkerImageUrl,
        setMarkerImageCover
    } from '$lib/editor/marker-image-editor.js';

    let {
        markerId = null,
        language = 'en',
        disabled = false,
        onChanged = async () => {},
        onImagesChange = () => {}
    } = $props();

    const TEXT = {
        en: {
            title: 'Marker photos',
            help: 'Add several images by URL/static path. Direct Cloudflare R2 upload comes in the upload phase.',
            saveFirst: 'Save the marker as a draft first, then you can add its photos.',
            source: 'Source',
            external: 'External URL',
            static: 'Static path',
            imageRef: 'Image URL / path',
            add: 'Add photo',
            adding: 'Adding…',
            cover: 'Cover',
            setCover: 'Set as cover',
            moveUp: 'Move up',
            moveDown: 'Move down',
            delete: 'Delete',
            none: 'No photos yet.',
            loadError: 'Could not load marker photos.',
            saveError: 'Could not add the photo.',
            deleteError: 'Could not delete the photo.',
            coverError: 'Could not change the cover.',
            reorderError: 'Could not reorder the photos.',
            required: 'Add a valid image URL or static path.',
            preview: 'Preview'
        },
        pt: {
            title: 'Fotos do marcador',
            help: 'Podes adicionar várias imagens por URL/caminho estático. O upload direto para Cloudflare R2 entra na fase de uploads.',
            saveFirst: 'Guarda primeiro o marcador como rascunho e depois podes adicionar as fotografias.',
            source: 'Origem',
            external: 'URL externo',
            static: 'Caminho estático',
            imageRef: 'URL / caminho da imagem',
            add: 'Adicionar foto',
            adding: 'A adicionar…',
            cover: 'Capa',
            setCover: 'Definir como capa',
            moveUp: 'Subir',
            moveDown: 'Descer',
            delete: 'Eliminar',
            none: 'Ainda não existem fotos.',
            loadError: 'Não foi possível carregar as fotos do marcador.',
            saveError: 'Não foi possível adicionar a foto.',
            deleteError: 'Não foi possível eliminar a foto.',
            coverError: 'Não foi possível alterar a capa.',
            reorderError: 'Não foi possível reordenar as fotografias.',
            required: 'Adiciona um URL ou caminho de imagem válido.',
            preview: 'Pré-visualização'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let images = $state([]);
    let loading = $state(false);
    let working = $state(false);
    let errorMessage = $state('');
    let source = $state('external');
    let imageRef = $state('');
    let loadedMarkerId = null;

    let previewUrl = $derived(resolveMarkerImageUrl({ source, imageRef: imageRef.trim() }));

    async function refresh() {
        if (!markerId) {
            images = [];
            onImagesChange([]);
            loadedMarkerId = null;
            return;
        }

        loading = true;
        errorMessage = '';
        try {
            images = await loadMarkerImages({
                supabase: getSupabaseBrowserClient(),
                markerId
            });
            loadedMarkerId = markerId;
            onImagesChange(images);
        } catch (error) {
            console.error('DeepMap marker images load:', error);
            errorMessage = t.loadError;
        } finally {
            loading = false;
        }
    }

    function resetNewImage() {
        source = 'external';
        imageRef = '';
    }

    async function addImage() {
        if (!markerId || working || disabled) return;
        if (!imageRef.trim()) {
            errorMessage = t.required;
            return;
        }

        working = true;
        errorMessage = '';
        try {
            const nextOrder = images.length
                ? Math.max(...images.map((image) => image.sortOrder ?? 0)) + 10
                : 10;
            const shouldCover = images.length === 0;

            await createMarkerImage({
                supabase: getSupabaseBrowserClient(),
                markerId,
                image: {
                    source,
                    imageRef,
                    sortOrder: nextOrder,
                    isCover: shouldCover
                }
            });

            resetNewImage();
            await refresh();
            await onChanged({ action: 'image-added', markerId });
        } catch (error) {
            console.error('DeepMap marker image add:', error);
            errorMessage = t.saveError;
        } finally {
            working = false;
        }
    }

    async function setCover(imageId) {
        if (!markerId || working || disabled) return;
        working = true;
        errorMessage = '';
        try {
            await setMarkerImageCover({
                supabase: getSupabaseBrowserClient(),
                markerId,
                imageId
            });
            await refresh();
            await onChanged({ action: 'image-cover', markerId, imageId });
        } catch (error) {
            console.error('DeepMap marker image cover:', error);
            errorMessage = t.coverError;
        } finally {
            working = false;
        }
    }

    async function reorder(imageId, direction) {
        if (!markerId || working || disabled) return;
        working = true;
        errorMessage = '';
        try {
            await moveMarkerImage({
                supabase: getSupabaseBrowserClient(),
                images,
                imageId,
                direction
            });
            await refresh();
            await onChanged({ action: 'image-reordered', markerId, imageId });
        } catch (error) {
            console.error('DeepMap marker image reorder:', error);
            errorMessage = t.reorderError;
        } finally {
            working = false;
        }
    }

    async function removeImage(imageId) {
        if (!markerId || working || disabled) return;
        working = true;
        errorMessage = '';
        try {
            const removed = images.find((image) => image.id === imageId);
            const supabase = getSupabaseBrowserClient();
            await deleteMarkerImage({ supabase, imageId });
            await refresh();

            if (removed?.isCover && images.length) {
                await setMarkerImageCover({
                    supabase,
                    markerId,
                    imageId: images[0].id
                });
                await refresh();
            }

            await onChanged({ action: 'image-deleted', markerId, imageId });
        } catch (error) {
            console.error('DeepMap marker image delete:', error);
            errorMessage = t.deleteError;
        } finally {
            working = false;
        }
    }

    $effect(() => {
        if (markerId === loadedMarkerId) return;
        void refresh();
    });
</script>

<section class="images-panel">
    <div class="heading">
        <strong>{t.title}</strong>
        {#if markerId}<span>{images.length}</span>{/if}
    </div>

    {#if !markerId}
        <p class="help">{t.saveFirst}</p>
    {:else}
        <p class="help">{t.help}</p>

        {#if images.length}
            <div class="image-list">
                {#each images as image, index (image.id)}
                    <article class="image-card">
                        {#if resolveMarkerImageUrl(image)}
                            <img src={resolveMarkerImageUrl(image)} alt="" />
                        {:else}
                            <div class="image-placeholder">R2</div>
                        {/if}

                        <div class="image-card-copy">
                            <div class="image-meta">
                                <strong>{image.isCover ? t.cover : `#${index + 1}`}</strong>
                                <small>{image.imageRef}</small>
                            </div>

                            <div class="image-actions">
                                <button
                                    type="button"
                                    title={t.moveUp}
                                    aria-label={t.moveUp}
                                    onclick={() => reorder(image.id, 'up')}
                                    disabled={working || disabled || index === 0}
                                >↑</button>
                                <button
                                    type="button"
                                    title={t.moveDown}
                                    aria-label={t.moveDown}
                                    onclick={() => reorder(image.id, 'down')}
                                    disabled={working || disabled || index === images.length - 1}
                                >↓</button>
                                {#if !image.isCover}
                                    <button type="button" onclick={() => setCover(image.id)} disabled={working || disabled}>{t.setCover}</button>
                                {/if}
                                <button class="danger" type="button" onclick={() => removeImage(image.id)} disabled={working || disabled}>{t.delete}</button>
                            </div>
                        </div>
                    </article>
                {/each}
            </div>
        {:else if !loading}
            <p class="empty">{t.none}</p>
        {/if}

        <details class="add-photo">
            <summary>{t.add}</summary>
            <div class="add-body">
                <label>
                    <span>{t.source}</span>
                    <select bind:value={source} disabled={working || disabled}>
                        <option value="external">{t.external}</option>
                        <option value="static">{t.static}</option>
                    </select>
                </label>

                <label>
                    <span>{t.imageRef}</span>
                    <input
                        bind:value={imageRef}
                        placeholder={source === 'static' ? '/games/elden-ring/locations/example.webp' : 'https://…'}
                        disabled={working || disabled}
                    />
                </label>

                {#if previewUrl}
                    <div class="live-preview">
                        <img src={previewUrl} alt="" />
                        <span>{t.preview}</span>
                    </div>
                {/if}

                <button class="primary" type="button" onclick={addImage} disabled={working || disabled}>
                    {working ? t.adding : t.add}
                </button>
            </div>
        </details>
    {/if}

    {#if errorMessage}<p class="error" role="alert">{errorMessage}</p>{/if}
</section>

<style>
    .images-panel { margin:10px 0; padding:10px; border:1px solid #303039; border-radius:7px; background:#101015; }
    .heading { display:flex; align-items:center; justify-content:space-between; gap:8px; }
    .heading strong { color:#e4e4e8; font-size:.78rem; }
    .heading span { min-width:22px; padding:2px 6px; border:1px solid #3a3528; border-radius:999px; color:#d8b86f; text-align:center; font-size:.62rem; }
    .help,.empty { margin:7px 0; color:#888892; font-size:.69rem; line-height:1.4; }
    .image-list { display:grid; gap:7px; margin-top:8px; }
    .image-card { display:grid; grid-template-columns:82px minmax(0,1fr); gap:8px; padding:7px; border:1px solid #292932; border-radius:6px; background:#0b0b0e; }
    .image-card img,.image-placeholder { width:82px; height:62px; border-radius:5px; object-fit:cover; background:#17171d; }
    .image-placeholder { display:grid; place-items:center; color:#8f8f98; font-size:.7rem; }
    .image-card-copy { min-width:0; display:grid; align-content:center; gap:6px; }
    .image-meta { min-width:0; display:grid; gap:3px; }
    .image-meta strong { color:#d8b86f; font-size:.68rem; }
    .image-meta small { overflow:hidden; color:#9d9da6; font-size:.63rem; text-overflow:ellipsis; white-space:nowrap; }
    .image-actions { display:flex; flex-wrap:wrap; gap:5px; }
    button { cursor:pointer; }
    button:disabled { opacity:.38; cursor:not-allowed; }
    .image-actions button { padding:5px 7px; border:1px solid #544a35; border-radius:4px; background:#17171c; color:#d6b96e; font-size:.61rem; font-weight:800; }
    .image-actions .danger { border-color:#704040; color:#d99595; }
    .add-photo { margin-top:9px; border-top:1px solid #292932; padding-top:8px; }
    .add-photo summary { cursor:pointer; color:#d8b86f; font-size:.7rem; font-weight:800; }
    .add-body { padding-top:8px; }
    label { display:grid; gap:5px; margin-bottom:8px; }
    label>span { color:#b8b8c0; font-size:.66rem; font-weight:700; }
    input,select { width:100%; box-sizing:border-box; padding:7px 8px; border:1px solid #34343e; border-radius:5px; background:#0b0b0e; color:#f4f4f5; font:inherit; font-size:.74rem; }
    .live-preview { position:relative; margin:0 0 8px; overflow:hidden; border:1px solid #34343e; border-radius:6px; background:#09090c; }
    .live-preview img { display:block; width:100%; max-height:150px; object-fit:contain; }
    .live-preview span { position:absolute; left:6px; bottom:6px; padding:3px 5px; border-radius:4px; background:rgba(0,0,0,.75); color:#d8b86f; font-size:.58rem; font-weight:800; text-transform:uppercase; }
    .primary { width:100%; padding:8px 10px; border:1px solid #c8a355; border-radius:5px; background:#c8a355; color:#111116; font-weight:800; }
    .error { margin:8px 0 0; padding:7px 8px; border:1px solid rgba(192,88,88,.5); border-radius:5px; background:rgba(120,35,35,.18); color:#efb2b2; font-size:.68rem; }
</style>
