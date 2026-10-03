<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import MarkerImagesPanel from '$lib/editor/MarkerImagesPanel.svelte';
    import MarkerContentEditor from '$lib/editor/MarkerContentEditor.svelte';
    import CoordinateStepper from '$lib/editor/CoordinateStepper.svelte';
    import { loadEditorMarkerContent, replaceEditorMarkerContent } from '$lib/editor/marker-content.js';
    import { getVideoEmbedUrl, normaliseHttpUrl } from '$lib/map/media.js';
    import {
        createEditorMarker,
        deleteEditorMarker,
        loadEditorMarkers,
        slugifyMarkerTitle,
        updateEditorMarker
    } from '$lib/editor/marker-editor.js';

    let {
        gameId,
        language = 'en',
        active = false,
        point = null,
        selectedMarkerId = null,
        categories = {},
        categoryGroups = [],
        mapDefinitions = {},
        onChanged = async () => {},
        onPreview = () => {},
        onSelectionChange = () => {},
        positionModeActive = false,
        onPositionModeChange = () => {},
        onMoveStateChange = () => {},
        onOriginalVisibilityChange = () => {}
    } = $props();

    const TEXT = {
        en: {
            title: 'Marker editor',
            newMarker: 'New marker',
            existingMarker: 'Existing marker',
            drafts: 'Drafts',
            publishedMarkers: 'Published',
            chooseDraft: 'Choose a draft…',
            choosePublished: 'Choose a published marker…',
            noDrafts: 'No drafts.',
            noPublished: 'No published markers.',
            refresh: 'Refresh',
            layer: 'Layer',
            type: 'Type',
            category: 'Category',
            chooseCategory: 'Choose a category…',
            slug: 'Slug',
            titleEn: 'Title — EN',
            titlePt: 'Title — PT',
            descriptionEn: 'Description — EN',
            descriptionPt: 'Description — PT',
            region: 'Region',
            video: 'Video URL',
            videoPreview: 'Video preview',
            openVideo: 'Open video',
            invalidVideo: 'Use a valid http(s) video URL.',
            x: 'X',
            y: 'Y',
            saveDraft: 'Save draft',
            saveChanges: 'Save changes',
            publish: 'Publish',
            moveDraft: 'Move to draft',
            saving: 'Saving…',
            delete: 'Delete',
            deleting: 'Deleting…',
            saved: 'Marker saved.',
            deleted: 'Marker deleted.',
            clickMap: 'New marker: click the map to choose its position. Existing marker: use Change position.',
            required: 'Fill both titles, category, layer and valid coordinates.',
            slugInvalid: 'Slug must use lowercase letters, numbers and hyphens.',
            loadError: 'Could not load editor markers.',
            saveError: 'Could not save the marker.',
            deleteError: 'Could not delete the marker.',
            confirmDelete: 'Delete this marker? This cannot be undone.',
            advanced: 'Advanced',
            autoSlugHelp: 'Generated automatically from the English title. Edit only when needed.',
            showOriginal: 'Show original location',
            showOriginalHelp: 'Useful for fine adjustments.',
            changePosition: 'Change position',
            choosingPosition: 'Click the map…',
            cancelEdit: 'Cancel editing',
            publishedBy: 'Published by',
            lastEditedBy: 'Modified by',
            approvedBy: 'Approved by',
            livePreview: 'Live preview',
            auditUnavailable: 'Attribution not available yet',
            draftSaved: 'Draft saved.',
            publishedSaved: 'Marker published.',
            changesSaved: 'Changes saved.'
        },
        pt: {
            title: 'Editor de marcador',
            newMarker: 'Novo marcador',
            existingMarker: 'Marcador existente',
            drafts: 'Rascunhos',
            publishedMarkers: 'Publicados',
            chooseDraft: 'Escolhe um rascunho…',
            choosePublished: 'Escolhe um marcador publicado…',
            noDrafts: 'Sem rascunhos.',
            noPublished: 'Sem marcadores publicados.',
            refresh: 'Atualizar',
            layer: 'Camada',
            type: 'Tipo',
            category: 'Categoria',
            chooseCategory: 'Escolhe uma categoria…',
            slug: 'Slug',
            titleEn: 'Título — EN',
            titlePt: 'Título — PT',
            descriptionEn: 'Descrição — EN',
            descriptionPt: 'Descrição — PT',
            region: 'Região',
            video: 'URL do vídeo',
            videoPreview: 'Pré-visualização do vídeo',
            openVideo: 'Abrir vídeo',
            invalidVideo: 'Usa um URL de vídeo http(s) válido.',
            x: 'X',
            y: 'Y',
            saveDraft: 'Guardar rascunho',
            saveChanges: 'Guardar alterações',
            publish: 'Publicar',
            moveDraft: 'Passar a rascunho',
            saving: 'A guardar…',
            delete: 'Eliminar',
            deleting: 'A eliminar…',
            saved: 'Marcador guardado.',
            deleted: 'Marcador eliminado.',
            clickMap: 'Novo marcador: clica no mapa para escolher a posição. Marcador existente: usa Mudar posição.',
            required: 'Preenche os dois títulos, categoria, camada e coordenadas válidas.',
            slugInvalid: 'O slug só pode ter letras minúsculas, números e hífenes.',
            loadError: 'Não foi possível carregar os marcadores do editor.',
            saveError: 'Não foi possível guardar o marcador.',
            deleteError: 'Não foi possível eliminar o marcador.',
            confirmDelete: 'Eliminar este marcador? Esta ação não pode ser anulada.',
            advanced: 'Avançado',
            autoSlugHelp: 'Gerado automaticamente a partir do título EN. Altera apenas se precisares.',
            showOriginal: 'Mostrar localização original',
            showOriginalHelp: 'Útil para pequenos retoques.',
            changePosition: 'Mudar posição',
            choosingPosition: 'Clica no mapa…',
            cancelEdit: 'Cancelar edição',
            publishedBy: 'Publicado por',
            lastEditedBy: 'Modificado por',
            approvedBy: 'Aprovado por',
            livePreview: 'Pré-visualização',
            auditUnavailable: 'Autoria ainda não disponível',
            draftSaved: 'Rascunho guardado.',
            publishedSaved: 'Marcador publicado.',
            changesSaved: 'Alterações guardadas.'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);

    let markers = $state([]);
    let loading = $state(false);
    let saving = $state(false);
    let deleting = $state(false);
    let errorMessage = $state('');
    let successMessage = $state('');
    let loadedOnce = false;
    let lastPointRevision = null;
    let lastSelectedMarkerId = null;

    let editingId = $state(null);
    let mapLayer = $state('surface');
    let categoryGroupId = $state('');
    let categoryId = $state('');
    let slug = $state('');
    let manualSlug = $state(false);
    let titleEn = $state('');
    let titlePt = $state('');
    let descriptionEn = $state('');
    let descriptionPt = $state('');
    let regionId = $state('');
    let videoUrl = $state('');
    let coordinateX = $state('');
    let coordinateY = $state('');
    let isPublished = $state(false);
    let showOriginalLocation = $state(false);
    let markerMoved = $state(false);
    let contentItems = $state([]);
    let contentLoadToken = 0;

    let sortedGroups = $derived(
        [...categoryGroups].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );

    let sortedCategories = $derived(
        Object.values(categories).sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );

    let filteredCategories = $derived(
        sortedCategories.filter((category) => !categoryGroupId || category.group === categoryGroupId)
    );

    let sortedLayers = $derived(
        Object.values(mapDefinitions).sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );

    let draftMarkers = $derived(markers.filter((marker) => !marker.isPublished));
    let publishedMarkers = $derived(markers.filter((marker) => marker.isPublished));
    let selectedMarker = $derived(
        editingId === null ? null : markers.find((marker) => marker.id === editingId) ?? null
    );

    let videoLinkUrl = $derived(normaliseHttpUrl(videoUrl));
    let videoEmbedUrl = $derived(getVideoEmbedUrl(videoUrl));

    function localisedLabel(item) {
        return item?.label?.[language] ?? item?.label?.en ?? item?.label?.pt ?? item?.id ?? '';
    }

    function formatAuditDate(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return new Intl.DateTimeFormat(language === 'pt' ? 'pt-PT' : 'en-GB', {
            dateStyle: 'medium',
            timeStyle: 'short'
        }).format(date);
    }

    function clearMessages() {
        errorMessage = '';
        successMessage = '';
    }

    function resetForm({ keepCoordinates = true } = {}) {
        editingId = null;
        mapLayer = sortedLayers[0]?.id ?? 'surface';
        categoryGroupId = sortedGroups[0]?.id ?? '';
        categoryId = '';
        slug = '';
        manualSlug = false;
        titleEn = '';
        titlePt = '';
        descriptionEn = '';
        descriptionPt = '';
        regionId = '';
        videoUrl = '';
        contentItems = [];
        isPublished = false;

        if (!keepCoordinates) {
            coordinateX = '';
            coordinateY = '';
        }

        showOriginalLocation = false;
        markerMoved = false;
        clearMessages();
        onSelectionChange(null);
        onPositionModeChange(false);
        onMoveStateChange(false);
        onOriginalVisibilityChange(false);
        onPreview(null, { clear: true });
    }

    function loadMarkerIntoForm(marker) {
        if (!marker) return;

        editingId = marker.id;
        mapLayer = marker.mapLayer;
        categoryId = marker.categoryId;
        categoryGroupId = categories[marker.categoryId]?.group ?? sortedGroups[0]?.id ?? '';
        slug = marker.slug;
        manualSlug = true;
        titleEn = marker.titleEn;
        titlePt = marker.titlePt;
        descriptionEn = marker.descriptionEn;
        descriptionPt = marker.descriptionPt;
        regionId = marker.regionId;
        videoUrl = marker.videoUrl;
        coordinateX = String(marker.coordinateX);
        coordinateY = String(marker.coordinateY);
        isPublished = marker.isPublished;
        showOriginalLocation = false;
        markerMoved = false;

        clearMessages();
        onPositionModeChange(false);
        onMoveStateChange(false);
        onOriginalVisibilityChange(false);
        onPreview(marker, { pan: true });
        void refreshMarkerContent(marker.id);
    }

    async function refreshMarkerContent(markerId) {
        const token = ++contentLoadToken;
        try {
            const items = await loadEditorMarkerContent({
                supabase: getSupabaseBrowserClient(),
                markerId
            });
            if (token === contentLoadToken && editingId === markerId) contentItems = items;
        } catch (error) {
            console.warn('DeepMap marker content load:', error);
            if (token === contentLoadToken && editingId === markerId) contentItems = [];
        }
    }

    function handleCategoryGroupChange() {
        if (categoryId && categories[categoryId]?.group !== categoryGroupId) categoryId = '';
    }

    async function refreshMarkers({ preserveSelection = true } = {}) {
        loading = true;
        errorMessage = '';
        const previousId = preserveSelection ? editingId : null;

        try {
            markers = await loadEditorMarkers({
                supabase: getSupabaseBrowserClient(),
                gameId
            });

            if (previousId !== null) {
                const same = markers.find((marker) => marker.id === previousId);
                if (same) loadMarkerIntoForm(same);
            }
        } catch (error) {
            console.error('DeepMap marker editor load:', error);
            errorMessage = t.loadError;
        } finally {
            loading = false;
        }
    }

    function chooseMarker(event) {
        const value = event.currentTarget.value;

        if (!value) {
            resetForm({ keepCoordinates: true });
            return;
        }

        const marker = markers.find((item) => String(item.id) === value);
        if (!marker) return;

        onSelectionChange(marker.id);
        loadMarkerIntoForm(marker);
    }

    function buildMarkerInput(nextPublished = isPublished) {
        const autoSlug = slugifyMarkerTitle(titleEn || titlePt);
        return {
            mapLayer,
            categoryId,
            slug: (slug.trim() || autoSlug),
            titleEn,
            titlePt,
            descriptionEn,
            descriptionPt,
            regionId,
            videoUrl,
            coordinateX: Number(coordinateX),
            coordinateY: Number(coordinateY),
            isPublished: nextPublished
        };
    }


    function validate(marker) {
        if (
            !marker.mapLayer ||
            !marker.categoryId ||
            !marker.titleEn.trim() ||
            !marker.titlePt.trim() ||
            !Number.isFinite(marker.coordinateX) ||
            !Number.isFinite(marker.coordinateY)
        ) {
            return t.required;
        }

        if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(marker.slug)) {
            return t.slugInvalid;
        }

        if (marker.videoUrl?.trim() && !normaliseHttpUrl(marker.videoUrl)) {
            return t.invalidVideo;
        }

        return '';
    }

    async function saveMarker(nextPublished) {
        if (saving || deleting) return;

        clearMessages();
        const markerInput = buildMarkerInput(nextPublished);
        const validationError = validate(markerInput);

        if (validationError) {
            errorMessage = validationError;
            return;
        }

        const wasEditing = editingId !== null;
        const wasPublished = isPublished;

        slug = markerInput.slug;
        saving = true;

        try {
            const supabase = getSupabaseBrowserClient();
            const saved = editingId === null
                ? await createEditorMarker({ supabase, gameId, marker: markerInput })
                : await updateEditorMarker({
                    supabase,
                    gameId,
                    markerId: editingId,
                    marker: markerInput
                });

            await replaceEditorMarkerContent({
                supabase,
                markerId: saved.id,
                items: contentItems
            });

            await refreshMarkers({ preserveSelection: false });

            // Guardar/publicar termina a operação atual.
            // O marcador volta a ser selecionado apenas se o admin o escolher outra vez.
            resetForm({ keepCoordinates: false });

            successMessage = nextPublished
                ? (wasEditing && wasPublished ? t.changesSaved : t.publishedSaved)
                : t.draftSaved;

            await onChanged({ action: 'save', marker: saved });
        } catch (error) {
            console.error('DeepMap marker editor save:', error);
            errorMessage = error?.code === '23505'
                ? (language === 'pt' ? 'Já existe um marcador com esse slug neste jogo.' : 'A marker with that slug already exists in this game.')
                : t.saveError;
        } finally {
            saving = false;
        }
    }

    function togglePositionMode() {
        if (editingId === null || saving || deleting) return;
        onPositionModeChange(!positionModeActive);
    }

    function cancelEditing() {
        resetForm({ keepCoordinates: false });
    }

    async function removeMarker() {
        if (editingId === null || saving || deleting) return;
        if (!window.confirm(t.confirmDelete)) return;

        deleting = true;
        clearMessages();

        try {
            const deletedId = editingId;

            await deleteEditorMarker({
                supabase: getSupabaseBrowserClient(),
                gameId,
                markerId: deletedId
            });

            resetForm({ keepCoordinates: false });
            await refreshMarkers({ preserveSelection: false });
            successMessage = t.deleted;
            await onChanged({ action: 'delete', markerId: deletedId });
        } catch (error) {
            console.error('DeepMap marker editor delete:', error);
            errorMessage = t.deleteError;
        } finally {
            deleting = false;
        }
    }

    $effect(() => {
        if (!active || loadedOnce) return;
        loadedOnce = true;
        void refreshMarkers({ preserveSelection: false });
    });

    $effect(() => {
        const revision = point?.revision ?? null;
        if (!active || revision === null || revision === lastPointRevision) return;

        lastPointRevision = revision;
        coordinateX = String(point.x);
        coordinateY = String(point.y);
        successMessage = '';
        if (editingId !== null) {
            markerMoved = true;
            onMoveStateChange(true);
            onPositionModeChange(false);
        }
    });

    $effect(() => {
        if (!active) return;

        if (selectedMarkerId === null) {
            lastSelectedMarkerId = null;
            return;
        }

        if (selectedMarkerId === lastSelectedMarkerId) return;

        lastSelectedMarkerId = selectedMarkerId;
        const marker = markers.find((item) => item.id === selectedMarkerId);
        if (marker) loadMarkerIntoForm(marker);
    });

    // Slug automático enquanto o marcador ainda é novo e o utilizador não o editou manualmente.
    $effect(() => {
        if (!active || editingId !== null || manualSlug) return;
        slug = slugifyMarkerTitle(titleEn || titlePt);
    });

    function hasCoordinateValue(value) {
        return String(value ?? '').trim() !== '' && Number.isFinite(Number(value));
    }

    // O próprio mapa é a pré-visualização: só atualiza o ponto em edição.
    $effect(() => {
        if (!active) return;
        if (!hasCoordinateValue(coordinateX) || !hasCoordinateValue(coordinateY)) {
            onPreview(null, { clear: true });
            return;
        }
        const x = Number(coordinateX);
        const y = Number(coordinateY);
        const category = categoryId;
        const layer = mapLayer;
        if (!Number.isFinite(x) || !Number.isFinite(y)) {
            onPreview(null, { clear: true });
            return;
        }
        onPreview({
            id: editingId,
            databaseId: editingId,
            coordinateX: x,
            coordinateY: y,
            categoryId: category,
            mapLayer: layer,
            previewOnly: true
        }, { pan: false, lightweight: true });
    });
</script>

{#if active}
    <section class="marker-editor-panel" aria-label={t.title}>
        <div class="panel-heading">
            <div>
                <span class="eyebrow">{t.title}</span>
                <strong>{editingId === null ? t.newMarker : t.existingMarker}</strong>
            </div>

            <button class="small-button" type="button" onclick={() => refreshMarkers()} disabled={loading || saving || deleting}>
                {t.refresh}
            </button>
        </div>

        <div class="marker-library">
            <div class="marker-library-heading">
                <strong>{t.existingMarker}</strong>
                <button class="small-button" type="button" onclick={() => resetForm({ keepCoordinates: true })} disabled={saving || deleting}>
                    {t.newMarker}
                </button>
            </div>

            <label class="marker-status-list">
                <span class="status-heading">
                    <span>{t.drafts}</span>
                    <b>{draftMarkers.length}</b>
                </span>
                <select
                    onchange={chooseMarker}
                    value={selectedMarker && !selectedMarker.isPublished ? String(selectedMarker.id) : ''}
                    disabled={loading || saving || deleting}
                >
                    <option value="">{draftMarkers.length ? t.chooseDraft : t.noDrafts}</option>
                    {#each draftMarkers as marker}
                        <option value={String(marker.id)}>{marker.titleEn} — {marker.slug}</option>
                    {/each}
                </select>
            </label>

            <label class="marker-status-list">
                <span class="status-heading">
                    <span>{t.publishedMarkers}</span>
                    <b>{publishedMarkers.length}</b>
                </span>
                <select
                    onchange={chooseMarker}
                    value={selectedMarker?.isPublished ? String(selectedMarker.id) : ''}
                    disabled={loading || saving || deleting}
                >
                    <option value="">{publishedMarkers.length ? t.choosePublished : t.noPublished}</option>
                    {#each publishedMarkers as marker}
                        <option value={String(marker.id)}>
                            {marker.titleEn}{marker.createdByUsername ? ` — @${marker.createdByUsername}` : ` — ${marker.slug}`}
                        </option>
                    {/each}
                </select>
            </label>
        </div>

        <p class="editor-help">{t.clickMap}</p>

        <div class="form-grid two-columns">
            <label>
                <span>{t.layer}</span>
                <select bind:value={mapLayer} disabled={saving || deleting}>
                    {#each sortedLayers as layer}
                        <option value={layer.id}>{localisedLabel(layer)}</option>
                    {/each}
                </select>
            </label>

            <label>
                <span>{t.type}</span>
                <select bind:value={categoryGroupId} onchange={handleCategoryGroupChange} disabled={saving || deleting}>
                    {#each sortedGroups as group}
                        <option value={group.id}>{localisedLabel(group)}</option>
                    {/each}
                </select>
            </label>
        </div>

        <label>
            <span>{t.category}</span>
            <select bind:value={categoryId} disabled={saving || deleting}>
                <option value="">{t.chooseCategory}</option>
                {#each filteredCategories as category}
                    <option value={category.id}>{localisedLabel(category)}</option>
                {/each}
            </select>
        </label>

        <div class="form-grid two-columns">
            <label>
                <span>{t.titleEn}</span>
                <input bind:value={titleEn} disabled={saving || deleting} />
            </label>

            <label>
                <span>{t.titlePt}</span>
                <input bind:value={titlePt} disabled={saving || deleting} />
            </label>
        </div>

        <div class="form-grid two-columns coordinates-grid">
            <label>
                <span>{t.x}</span>
                <CoordinateStepper axis="x" bind:value={coordinateX} disabled={saving || deleting} />
            </label>

            <label>
                <span>{t.y}</span>
                <CoordinateStepper axis="y" bind:value={coordinateY} disabled={saving || deleting} />
            </label>
        </div>

        {#if selectedMarker}
            <div class="position-toolbar">
                <button
                    class:active={positionModeActive}
                    class="position-button"
                    type="button"
                    onclick={togglePositionMode}
                    disabled={saving || deleting}
                >
                    {positionModeActive ? t.choosingPosition : t.changePosition}
                </button>

                {#if markerMoved}
                    <label class="original-location-toggle compact">
                        <input
                            type="checkbox"
                            bind:checked={showOriginalLocation}
                            onchange={() => onOriginalVisibilityChange(showOriginalLocation)}
                            disabled={saving || deleting}
                        />
                        <span>{t.showOriginal}</span>
                    </label>
                {/if}
            </div>
            {#if markerMoved && showOriginalLocation}
                <small class="position-help">{t.showOriginalHelp}</small>
            {/if}
        {/if}

        {#if selectedMarker}
            <div class="audit-row">
                {#if selectedMarker.createdByUsername}
                    <span>
                        {t.publishedBy}
                        <strong>@{selectedMarker.createdByUsername}</strong>
                        {#if selectedMarker.auditCreatedAt}<small>{formatAuditDate(selectedMarker.auditCreatedAt)}</small>{/if}
                    </span>
                {/if}
                {#if selectedMarker.updatedByUsername && selectedMarker.auditUpdatedAt && selectedMarker.auditUpdatedAt !== selectedMarker.auditCreatedAt}
                    <span>
                        {t.lastEditedBy}
                        <strong>@{selectedMarker.updatedByUsername}</strong>
                        <small>{formatAuditDate(selectedMarker.auditUpdatedAt)}</small>
                    </span>
                {/if}
                {#if selectedMarker.approvedByUsername}
                    <span>
                        {t.approvedBy}
                        <strong>@{selectedMarker.approvedByUsername}</strong>
                        {#if selectedMarker.approvedAt}<small>{formatAuditDate(selectedMarker.approvedAt)}</small>{/if}
                    </span>
                {/if}
            </div>
        {/if}

        <label>
            <span>{t.region}</span>
            <input bind:value={regionId} placeholder="Limgrave" disabled={saving || deleting} />
        </label>


        <label>
            <span>{t.descriptionEn}</span>
            <textarea rows="3" bind:value={descriptionEn} disabled={saving || deleting}></textarea>
        </label>

        <label>
            <span>{t.descriptionPt}</span>
            <textarea rows="3" bind:value={descriptionPt} disabled={saving || deleting}></textarea>
        </label>

        <label>
            <span>{t.video}</span>
            <input type="url" bind:value={videoUrl} placeholder="https://…" disabled={saving || deleting} />
        </label>

        {#if videoEmbedUrl}
            <div class="video-preview">
                <span>{t.videoPreview}</span>
                <iframe
                    src={videoEmbedUrl}
                    title={t.videoPreview}
                    loading="lazy"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                    allowfullscreen
                ></iframe>
            </div>
        {:else if videoLinkUrl}
            <a class="video-link-preview" href={videoLinkUrl} target="_blank" rel="noreferrer">
                ▶ {t.openVideo}
            </a>
        {:else if videoUrl.trim()}
            <p class="inline-warning">{t.invalidVideo}</p>
        {/if}

        <MarkerContentEditor {language} bind:value={contentItems} disabled={saving || deleting} />

        <MarkerImagesPanel
            markerId={editingId}
            {language}
            disabled={saving || deleting}
            {onChanged}
        />

        <details class="section-fold advanced-fold">
            <summary>{t.advanced}</summary>
            <div class="fold-body advanced-body">
                <label>
                    <span>{t.slug}</span>
                    <input
                        bind:value={slug}
                        oninput={() => manualSlug = true}
                        placeholder="church-of-elleh"
                        disabled={saving || deleting}
                    />
                    <small>{t.autoSlugHelp}</small>
                </label>
            </div>
        </details>

        <div class="editor-actions">
            {#if isPublished}
                <button class="primary-button" type="button" onclick={() => saveMarker(true)} disabled={saving || deleting}>
                    {saving ? t.saving : t.saveChanges}
                </button>
                <button class="secondary-button" type="button" onclick={() => saveMarker(false)} disabled={saving || deleting}>
                    {t.moveDraft}
                </button>
            {:else}
                <button class="secondary-button" type="button" onclick={() => saveMarker(false)} disabled={saving || deleting}>
                    {saving ? t.saving : t.saveDraft}
                </button>
                <button class="primary-button" type="button" onclick={() => saveMarker(true)} disabled={saving || deleting}>
                    {saving ? t.saving : t.publish}
                </button>
            {/if}

            {#if editingId !== null}
                <button class="secondary-button" type="button" onclick={cancelEditing} disabled={saving || deleting}>
                    {t.cancelEdit}
                </button>
                <button class="danger-button" type="button" onclick={removeMarker} disabled={saving || deleting}>
                    {deleting ? t.deleting : t.delete}
                </button>
            {/if}
        </div>

        {#if errorMessage}
            <p class="message error" role="alert">{errorMessage}</p>
        {/if}

        {#if successMessage}
            <p class="message success" role="status">{successMessage}</p>
        {/if}
    </section>
{/if}

<style>
    .marker-editor-panel {
        max-height: none;
        overflow: visible;
        padding: 14px;
        box-sizing: border-box;
        background: rgba(16, 16, 20, 0.98);
        border: 1px solid rgba(200, 163, 85, 0.7);
        border-radius: 9px;
        box-shadow: 0 10px 34px rgba(0, 0, 0, 0.62);
        pointer-events: auto;
        color: #f0f0f2;
    }

    .panel-heading,
    .editor-actions {
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .panel-heading {
        justify-content: space-between;
        margin-bottom: 10px;
    }

    .panel-heading > div {
        display: grid;
        gap: 2px;
    }

    .eyebrow {
        color: #c8a355;
        font-size: 0.66rem;
        font-weight: 800;
        text-transform: uppercase;
        letter-spacing: 0.08em;
    }

    .panel-heading strong {
        font-size: 0.95rem;
    }

    .marker-library {
        display: grid;
        gap: 8px;
        margin-bottom: 10px;
        padding: 9px;
        border: 1px solid #2c2c34;
        border-radius: 7px;
        background: rgba(10, 10, 13, 0.72);
    }

    .marker-library-heading,
    .status-heading {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
    }

    .marker-library-heading strong {
        color: #ededf0;
        font-size: 0.74rem;
    }

    .marker-status-list {
        display: grid;
        gap: 5px;
    }

    .status-heading {
        color: #a9a9b2;
        font-size: 0.67rem;
        font-weight: 800;
    }

    .status-heading b {
        min-width: 22px;
        padding: 2px 6px;
        border: 1px solid #3a3528;
        border-radius: 999px;
        background: rgba(200, 163, 85, 0.08);
        color: #d8b86f;
        text-align: center;
        font-size: 0.62rem;
    }

    .editor-help {
        margin: 8px 0 10px;
        color: #9797a1;
        font-size: 0.72rem;
        line-height: 1.4;
    }

    .section-fold {
        margin: 0 0 10px;
        border: 1px solid #303039;
        border-radius: 7px;
        background: #111116;
    }

    .section-fold > summary {
        cursor: pointer;
        padding: 9px 10px;
        color: #d8b86f;
        font-size: 0.72rem;
        font-weight: 800;
    }

    .fold-body {
        padding: 0 8px 8px;
    }

    .advanced-body small {
        color: #7f7f89;
        font-size: 0.62rem;
        line-height: 1.35;
    }

    label {
        display: grid;
        gap: 5px;
        margin-bottom: 9px;
    }

    label > span {
        color: #b8b8c0;
        font-size: 0.69rem;
        font-weight: 700;
    }

    input,
    select,
    textarea {
        width: 100%;
        box-sizing: border-box;
        padding: 8px 9px;
        border: 1px solid #34343e;
        border-radius: 5px;
        outline: none;
        background: #0b0b0e;
        color: #f4f4f5;
        font: inherit;
        font-size: 0.78rem;
    }

    textarea {
        resize: vertical;
    }

    input:focus,
    select:focus,
    textarea:focus {
        border-color: #c8a355;
        box-shadow: 0 0 0 2px rgba(200, 163, 85, 0.12);
    }


    .position-toolbar {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 7px;
        margin: -1px 0 7px;
    }

    .position-button {
        padding: 7px 10px;
        border: 1px solid #66593b;
        border-radius: 5px;
        background: #17171c;
        color: #d8b86f;
        font-size: .69rem;
        font-weight: 800;
        cursor: pointer;
    }

    .position-button.active {
        border-color: #d8b86f;
        background: rgba(200,163,85,.14);
        box-shadow: 0 0 0 2px rgba(200,163,85,.09);
    }

    .original-location-toggle.compact {
        display: flex;
        align-items: center;
        gap: 6px;
        margin: 0;
        padding: 6px 8px;
        border: 1px solid #2c2c34;
        border-radius: 5px;
        background: rgba(10,10,13,.52);
        cursor: pointer;
    }

    .original-location-toggle.compact input {
        width: auto;
        margin: 0;
        accent-color: #c8a355;
    }

    .original-location-toggle.compact span {
        color: #f0f0f2;
        font-size: 0.68rem;
        font-weight: 800;
    }

    .position-help,
    .audit-row small {
        color: #91919b;
        font-size: 0.63rem;
        line-height: 1.35;
    }

    .position-help {
        display: block;
        margin: -3px 0 9px;
    }

    .audit-row {
        display: grid;
        gap: 5px;
        margin: 0 0 9px;
        padding: 7px 8px;
        border-left: 2px solid rgba(200, 163, 85, 0.45);
        background: rgba(200, 163, 85, 0.035);
    }

    .audit-row > span {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: 5px;
        color: #aaaab3;
        font-size: 0.68rem;
    }

    .audit-row strong {
        color: #d8b86f;
    }

    .video-preview {
        display: grid;
        gap: 6px;
        margin: -1px 0 10px;
    }

    .video-preview > span {
        color: #b8b8c0;
        font-size: 0.67rem;
        font-weight: 700;
    }

    .video-preview iframe {
        width: 100%;
        aspect-ratio: 16 / 9;
        border: 1px solid #34343e;
        border-radius: 7px;
        background: #09090c;
    }

    .video-link-preview {
        display: flex;
        align-items: center;
        justify-content: center;
        margin: -1px 0 10px;
        padding: 8px 10px;
        border: 1px solid #544a35;
        border-radius: 6px;
        background: #111116;
        color: #d8b86f;
        font-size: 0.7rem;
        font-weight: 800;
        text-decoration: none;
    }

    .inline-warning {
        margin: -1px 0 10px;
        color: #e0a0a0;
        font-size: 0.66rem;
    }

    .form-grid {
        display: grid;
        gap: 8px;
    }

    .two-columns {
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    }

    .editor-actions {
        align-items: stretch;
        flex-wrap: wrap;
        margin-top: 10px;
    }

    button {
        cursor: pointer;
    }

    button:disabled {
        opacity: 0.48;
        cursor: not-allowed;
    }

    .primary-button,
    .secondary-button,
    .danger-button,
    .small-button {
        border-radius: 5px;
        font-weight: 800;
    }

    .primary-button {
        flex: 1;
        min-width: 120px;
        padding: 9px 12px;
        border: 1px solid #c8a355;
        background: #c8a355;
        color: #111116;
    }

    .secondary-button {
        flex: 1;
        min-width: 120px;
        padding: 9px 12px;
        border: 1px solid #6d5d39;
        background: #17171c;
        color: #d8b86f;
    }

    .danger-button {
        padding: 9px 12px;
        border: 1px solid #8e4e4e;
        background: transparent;
        color: #e0a0a0;
    }

    .small-button {
        padding: 7px 9px;
        border: 1px solid #544a35;
        background: #17171c;
        color: #d6b96e;
        font-size: 0.68rem;
    }

    .message {
        margin: 9px 0 0;
        padding: 8px 9px;
        border-radius: 5px;
        font-size: 0.72rem;
        line-height: 1.4;
    }

    .message.error {
        border: 1px solid rgba(192, 88, 88, 0.5);
        background: rgba(120, 35, 35, 0.18);
        color: #efb2b2;
    }

    .message.success {
        border: 1px solid rgba(87, 162, 106, 0.45);
        background: rgba(46, 110, 61, 0.17);
        color: #afe0b9;
    }

    @media (max-width: 640px) {
        .two-columns {
            grid-template-columns: 1fr;
        }

        .editor-actions {
            flex-direction: column;
        }

        .primary-button,
        .secondary-button,
        .danger-button {
            width: 100%;
        }
    }

</style>
