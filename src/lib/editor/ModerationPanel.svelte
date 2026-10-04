<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { normaliseHttpUrl } from '$lib/map/media.js';
    import CoordinateStepper from '$lib/editor/CoordinateStepper.svelte';
    import MarkerContentEditor from '$lib/editor/MarkerContentEditor.svelte';
    import { contentTypeLabel, serialiseMarkerContentItems } from '$lib/editor/marker-content.js';
    import {
        loadMarkerSubmissionsPage,
        reviewMarkerSubmission
    } from '$lib/community/marker-contributions.js';

    let {
        gameId,
        language = 'en',
        active = false,
        categories = {},
        categoryGroups = [],
        mapDefinitions = {},
        locations = [],
        point = null,
        positionModeActive = false,
        onPositionModeChange = () => {},
        onChanged = async () => {},
        onPreview = () => {}
    } = $props();

    const HISTORY_PAGE_SIZE = 10;
    const PENDING_LIMIT = 100;

    const TEXT = {
        en: {
            title: 'Moderation', pending: 'Pending submissions', refresh: 'Refresh', none: 'No pending submissions.',
            noneHelp: 'New community submissions will appear here when they need review.', history: 'History', backToPending: 'Pending',
            approvedTab: 'Approved', rejectedTab: 'Rejected', noHistory: 'No submissions in this history yet.',
            newMarker: 'New marker', correction: 'Correction', text: 'Text / region', location: 'Location', image: 'Image', other: 'Other',
            submittedBy: 'Submitted by', versions: 'versions', marker: 'Marker', note: 'Contributor note', reviewNote: 'Moderator note',
            reviewedBy: 'Reviewed by', reviewedAt: 'Reviewed', approve: 'Approve', reject: 'Reject', approving: 'Working…',
            approved: 'Submission approved.', rejected: 'Submission rejected.', loadError: 'Could not load moderation queue.',
            reviewError: 'Could not review this submission.', coordinates: 'Coordinates', category: 'Category', region: 'Region',
            changes: 'Submitted data', page: 'Page', content: 'Additional content', fullReview: 'Review / edit submission',
            layer: 'Map layer', type: 'Type', titleEn: 'Title — EN', titlePt: 'Title — PT', descriptionEn: 'Description — EN',
            descriptionPt: 'Description — PT', video: 'Video URL', chooseCategory: 'Choose a category…', optional: 'optional',
            required: 'Check the highlighted required fields.', requiredField: 'Required field.', invalidUrl: 'Use a valid http(s) URL.',
            choosePosition: 'Choose position on map', choosingPosition: 'Click the map…', imageUrl: 'Image URL', imageAction: 'Image action',
            addImage: 'Add image', reportImage: 'Report existing image', targetImage: 'Image ID', editedBeforeApproval: 'You can correct the submitted data before approving it.'
        },
        pt: {
            title: 'Moderação', pending: 'Submissões pendentes', refresh: 'Atualizar', none: 'Sem submissões pendentes.',
            noneHelp: 'As novas contribuições da comunidade aparecem aqui quando precisarem de revisão.', history: 'Histórico', backToPending: 'Pendentes',
            approvedTab: 'Aprovados', rejectedTab: 'Reprovados', noHistory: 'Ainda não existem submissões neste histórico.',
            newMarker: 'Novo marcador', correction: 'Correção', text: 'Texto / região', location: 'Localização', image: 'Imagem', other: 'Outro',
            submittedBy: 'Enviado por', versions: 'versões', marker: 'Marcador', note: 'Nota do utilizador', reviewNote: 'Nota da moderação',
            reviewedBy: 'Revisto por', reviewedAt: 'Revisto', approve: 'Aprovar', reject: 'Rejeitar', approving: 'A processar…',
            approved: 'Submissão aprovada.', rejected: 'Submissão reprovada.', loadError: 'Não foi possível carregar a fila de moderação.',
            reviewError: 'Não foi possível rever esta submissão.', coordinates: 'Coordenadas', category: 'Categoria', region: 'Região',
            changes: 'Dados submetidos', page: 'Página', content: 'Conteúdo adicional', fullReview: 'Rever / editar submissão',
            layer: 'Camada do mapa', type: 'Tipo', titleEn: 'Título — EN', titlePt: 'Título — PT', descriptionEn: 'Descrição — EN',
            descriptionPt: 'Descrição — PT', video: 'URL do vídeo', chooseCategory: 'Escolhe uma categoria…', optional: 'opcional',
            required: 'Revê os campos obrigatórios assinalados.', requiredField: 'Campo obrigatório.', invalidUrl: 'Usa um URL http(s) válido.',
            choosePosition: 'Escolher posição no mapa', choosingPosition: 'Clica no mapa…', imageUrl: 'URL da imagem', imageAction: 'Ação da imagem',
            addImage: 'Adicionar imagem', reportImage: 'Reportar imagem existente', targetImage: 'ID da imagem', editedBeforeApproval: 'Podes corrigir os dados submetidos antes de aprovar.'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let mode = $state('pending');
    let pendingItems = $state([]);
    let pendingTotal = $state(0);
    let historyItems = $state([]);
    let historyTotal = $state(0);
    let historyStatus = $state('approved');
    let historyPage = $state(1);
    let selectedId = $state(null);
    let loading = $state(false);
    let working = $state(false);
    let errorMessage = $state('');
    let successMessage = $state('');
    let reviewNote = $state('');
    let loadedOnce = false;
    let lastPointRevision = null;

    // Full moderation editor. This is a review copy; nothing touches the official
    // marker until the moderator presses Approve.
    let reviewMapLayer = $state('surface');
    let reviewCategoryGroupId = $state('');
    let reviewCategoryId = $state('');
    let reviewTitleEn = $state('');
    let reviewTitlePt = $state('');
    let reviewRegionId = $state('');
    let reviewDescriptionEn = $state('');
    let reviewDescriptionPt = $state('');
    let reviewVideoUrl = $state('');
    let reviewCoordinateX = $state('');
    let reviewCoordinateY = $state('');
    let reviewContentItems = $state([]);
    let reviewImageUrl = $state('');
    let reviewImageAction = $state('add');
    let reviewTargetImageId = $state('');
    let fieldErrors = $state({});

    let activeItems = $derived(mode === 'history' ? historyItems : pendingItems);
    let selected = $derived(selectedId == null ? null : activeItems.find((item) => item.id === selectedId) ?? null);
    let historyPageCount = $derived(Math.max(1, Math.ceil(historyTotal / HISTORY_PAGE_SIZE)));
    let sortedGroups = $derived([...categoryGroups].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)));
    let sortedCategories = $derived(Object.values(categories).slice().sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)));
    let filteredCategories = $derived(sortedCategories.filter((category) => !reviewCategoryGroupId || category.group === reviewCategoryGroupId));
    let sortedLayers = $derived(Object.values(mapDefinitions).slice().sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)));

    function localisedLabel(item) {
        return item?.label?.[language] ?? item?.label?.en ?? item?.label?.pt ?? item?.id ?? '';
    }

    function localisedCategory(id) {
        const category = categories[id];
        return category?.label?.[language] ?? category?.label?.en ?? category?.label?.pt ?? id ?? '—';
    }

    function kindLabel(item) {
        if (item.type === 'create') return t.newMarker;
        return ({ text: t.text, location: t.location, image: t.image, other: t.other }[item.correctionKind] ?? t.correction);
    }

    function formatDate(value) {
        if (!value) return '—';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '—';
        return new Intl.DateTimeFormat(language === 'pt' ? 'pt-PT' : 'en-GB', {
            dateStyle: 'medium', timeStyle: 'short'
        }).format(date);
    }

    function visibleHistoryPages() {
        const total = historyPageCount;
        const maxVisible = 5;
        let start = Math.max(1, historyPage - Math.floor(maxVisible / 2));
        let end = Math.min(total, start + maxVisible - 1);
        start = Math.max(1, end - maxVisible + 1);
        return Array.from({ length: end - start + 1 }, (_, index) => start + index);
    }

    function targetLocation(item) {
        if (!item?.markerId) return null;
        return locations.find((location) => Number(location.databaseId) === Number(item.markerId)) ?? null;
    }

    function payloadValue(payload, key, fallback = '') {
        if (payload && Object.prototype.hasOwnProperty.call(payload, key)) return payload[key] ?? '';
        return fallback ?? '';
    }

    function reviewItemsFrom(source = []) {
        return (Array.isArray(source) ? source : []).map((item) => ({
            type: item?.type ?? 'note',
            textEn: item?.textEn ?? item?.text_en ?? item?.text?.en ?? '',
            textPt: item?.textPt ?? item?.text_pt ?? item?.text?.pt ?? ''
        }));
    }

    function populateReviewForm(item) {
        const payload = item?.payload ?? {};
        const target = targetLocation(item);
        reviewMapLayer = String(payloadValue(payload, 'map_layer', target?.mapLayer ?? sortedLayers[0]?.id ?? 'surface'));
        reviewCategoryId = String(payloadValue(payload, 'category_id', target?.categoryId ?? ''));
        reviewCategoryGroupId = categories[reviewCategoryId]?.group ?? sortedGroups[0]?.id ?? '';
        reviewTitleEn = String(payloadValue(payload, 'title_en', target?.title?.en ?? ''));
        reviewTitlePt = String(payloadValue(payload, 'title_pt', target?.title?.pt ?? ''));
        reviewRegionId = String(payloadValue(payload, 'region_id', target?.regionId ?? ''));
        reviewDescriptionEn = String(payloadValue(payload, 'description_en', target?.description?.en ?? ''));
        reviewDescriptionPt = String(payloadValue(payload, 'description_pt', target?.description?.pt ?? ''));
        reviewVideoUrl = String(payloadValue(payload, 'video_url', target?.videoUrl ?? ''));
        reviewCoordinateX = String(payloadValue(payload, 'coordinate_x', target?.coordinates?.[1] ?? ''));
        reviewCoordinateY = String(payloadValue(payload, 'coordinate_y', target?.coordinates?.[0] ?? ''));
        reviewContentItems = reviewItemsFrom(Array.isArray(payload.content_items) ? payload.content_items : target?.contentItems ?? []);
        reviewImageUrl = String(payload.image_url ?? '');
        reviewImageAction = payload.image_action ?? 'add';
        reviewTargetImageId = payload.target_image_id == null ? '' : String(payload.target_image_id);
        fieldErrors = {};
    }

    function resolveSubmissionPreview(item) {
        if (item?.status === 'pending') {
            const x = Number(reviewCoordinateX);
            const y = Number(reviewCoordinateY);
            if (Number.isFinite(x) && Number.isFinite(y)) {
                return { coordinateX: x, coordinateY: y, categoryId: reviewCategoryId || null, mapLayer: reviewMapLayer || 'surface', previewOnly: true };
            }
        }

        const payload = item?.payload ?? {};
        const payloadX = Number(payload.coordinate_x);
        const payloadY = Number(payload.coordinate_y);
        if (Number.isFinite(payloadX) && Number.isFinite(payloadY)) {
            return { coordinateX: payloadX, coordinateY: payloadY, categoryId: payload.category_id ?? null, mapLayer: payload.map_layer ?? 'surface', previewOnly: true };
        }

        const marker = targetLocation(item);
        if (marker?.coordinates?.length >= 2) {
            return { databaseId: marker.databaseId, coordinateX: Number(marker.coordinates[1]), coordinateY: Number(marker.coordinates[0]), categoryId: marker.categoryId ?? null, mapLayer: marker.mapLayer ?? 'surface', previewOnly: true };
        }
        return null;
    }

    async function loadPending() {
        loading = true;
        errorMessage = '';
        try {
            const page = await loadMarkerSubmissionsPage({ supabase: getSupabaseBrowserClient(), gameId, status: 'pending', limit: PENDING_LIMIT, offset: 0 });
            pendingItems = page.items;
            pendingTotal = page.total;
            if (mode === 'pending' && selectedId !== null && !pendingItems.some((item) => item.id === selectedId)) {
                selectedId = null;
                onPreview(null, { clear: true });
            }
        } catch (error) {
            console.error('DeepMap moderation queue:', error);
            errorMessage = t.loadError;
        } finally { loading = false; }
    }

    async function loadHistory() {
        loading = true;
        errorMessage = '';
        selectedId = null;
        onPositionModeChange(false);
        onPreview(null, { clear: true });
        try {
            const page = await loadMarkerSubmissionsPage({
                supabase: getSupabaseBrowserClient(), gameId, status: historyStatus,
                limit: HISTORY_PAGE_SIZE, offset: (historyPage - 1) * HISTORY_PAGE_SIZE
            });
            historyItems = page.items;
            historyTotal = page.total;
        } catch (error) {
            console.error('DeepMap moderation history:', error);
            errorMessage = t.loadError;
        } finally { loading = false; }
    }

    async function refresh() { if (mode === 'history') await loadHistory(); else await loadPending(); }

    function selectSubmission(item) {
        selectedId = item.id;
        reviewNote = item.status === 'pending' ? '' : (item.reviewNote ?? '');
        successMessage = '';
        errorMessage = '';
        onPositionModeChange(false);
        populateReviewForm(item);
        const preview = resolveSubmissionPreview(item);
        if (preview) onPreview(preview, { pan: true }); else onPreview(null, { clear: true });
    }

    async function openHistory() { mode = 'history'; historyPage = 1; historyStatus = 'approved'; await loadHistory(); }
    async function openPending() { mode = 'pending'; selectedId = null; onPositionModeChange(false); onPreview(null, { clear: true }); await loadPending(); }
    async function setHistoryStatus(status) { if (historyStatus === status && historyPage === 1) return; historyStatus = status; historyPage = 1; await loadHistory(); }
    async function goHistoryPage(page) { if (page < 1 || page > historyPageCount || page === historyPage) return; historyPage = page; await loadHistory(); }

    function handleCategoryGroupChange() {
        if (reviewCategoryId && categories[reviewCategoryId]?.group !== reviewCategoryGroupId) reviewCategoryId = '';
        fieldErrors = { ...fieldErrors, category: undefined };
    }

    function hasCoordinateValue(value) {
        return String(value ?? '').trim() !== '' && Number.isFinite(Number(value));
    }

    function validateReview() {
        const errors = {};
        if (!reviewMapLayer) errors.layer = t.requiredField;
        if (!reviewCategoryId) errors.category = t.requiredField;
        if (!reviewTitleEn.trim()) errors.titleEn = t.requiredField;
        if (!hasCoordinateValue(reviewCoordinateX)) errors.coordinateX = t.requiredField;
        if (!hasCoordinateValue(reviewCoordinateY)) errors.coordinateY = t.requiredField;
        if (reviewVideoUrl.trim() && !normaliseHttpUrl(reviewVideoUrl)) errors.video = t.invalidUrl;
        if (reviewImageUrl.trim() && !normaliseHttpUrl(reviewImageUrl)) errors.image = t.invalidUrl;
        fieldErrors = errors;
        return Object.keys(errors).length === 0;
    }

    function buildReviewPayload() {
        const original = selected?.payload ?? {};
        return {
            ...original,
            map_layer: reviewMapLayer,
            category_id: reviewCategoryId,
            title_en: reviewTitleEn.trim(),
            title_pt: reviewTitlePt.trim() || reviewTitleEn.trim(),
            region_id: reviewRegionId.trim(),
            description_en: reviewDescriptionEn.trim(),
            description_pt: reviewDescriptionPt.trim(),
            video_url: reviewVideoUrl.trim(),
            coordinate_x: Number(reviewCoordinateX),
            coordinate_y: Number(reviewCoordinateY),
            content_items: serialiseMarkerContentItems(reviewContentItems),
            image_url: reviewImageUrl.trim(),
            image_action: reviewImageAction,
            target_image_id: reviewTargetImageId || null
        };
    }

    async function review(decision) {
        if (!selected || selected.status !== 'pending' || working) return;
        if (decision === 'approved' && !validateReview()) {
            errorMessage = t.required;
            return;
        }

        working = true;
        errorMessage = '';
        successMessage = '';
        try {
            const reviewedId = selected.id;
            await reviewMarkerSubmission({
                supabase: getSupabaseBrowserClient(),
                submissionId: selected.id,
                decision,
                reviewNote,
                payloadOverride: decision === 'approved' ? buildReviewPayload() : null
            });
            successMessage = decision === 'approved' ? t.approved : t.rejected;
            selectedId = null;
            onPositionModeChange(false);
            onPreview(null, { clear: true });
            await loadPending();
            await onChanged({ action: 'moderation-review', submissionId: reviewedId, decision });
        } catch (error) {
            console.error('DeepMap moderation review:', error);
            errorMessage = t.reviewError;
        } finally { working = false; }
    }

    function togglePositionMode() {
        if (!selected || selected.status !== 'pending' || working) return;
        onPositionModeChange(!positionModeActive);
    }

    $effect(() => {
        if (!active || loadedOnce) return;
        loadedOnce = true;
        void loadPending();
    });

    $effect(() => {
        const revision = point?.revision ?? null;
        if (!active || revision === null || revision === lastPointRevision || !selected || selected.status !== 'pending') return;
        lastPointRevision = revision;
        reviewCoordinateX = String(point.x);
        reviewCoordinateY = String(point.y);
        onPositionModeChange(false);
    });

    $effect(() => {
        if (!active || !selected || selected.status !== 'pending') return;
        const x = Number(reviewCoordinateX);
        const y = Number(reviewCoordinateY);
        if (!Number.isFinite(x) || !Number.isFinite(y)) return;
        onPreview({ coordinateX: x, coordinateY: y, categoryId: reviewCategoryId || null, mapLayer: reviewMapLayer || 'surface', previewOnly: true }, { pan: false, lightweight: true });
    });
</script>

{#if active}
    <section class="moderation-panel" aria-label={t.title}>
        <div class="panel-heading">
            <div><span class="eyebrow">{t.title}</span><strong>{mode === 'history' ? t.history : `${t.pending} (${pendingTotal})`}</strong></div>
            <div class="heading-actions">
                {#if mode === 'pending'}
                    <button class="small-button history-button" type="button" onclick={openHistory} disabled={loading || working}>{t.history}</button>
                {:else}
                    <button class="small-button" type="button" onclick={openPending} disabled={loading || working}>{t.backToPending}</button>
                {/if}
                <button class="small-button" type="button" onclick={refresh} disabled={loading || working}>{t.refresh}</button>
            </div>
        </div>

        {#if errorMessage}<p class="message error">{errorMessage}</p>{/if}
        {#if successMessage}<p class="message success">{successMessage}</p>{/if}

        {#if mode === 'history'}
            <div class="history-tabs" role="tablist" aria-label={t.history}>
                <button class:active={historyStatus === 'approved'} type="button" onclick={() => setHistoryStatus('approved')}>{t.approvedTab}</button>
                <button class:active={historyStatus === 'rejected'} type="button" onclick={() => setHistoryStatus('rejected')}>{t.rejectedTab}</button>
            </div>
        {/if}

        {#if loading}
            <div class="loading-card" aria-live="polite">…</div>
        {:else if !activeItems.length}
            <div class="empty-state">
                <div class="empty-icon" aria-hidden="true">✓</div>
                <strong>{mode === 'history' ? t.noHistory : t.none}</strong>
                {#if mode === 'pending'}<p>{t.noneHelp}</p>{/if}
            </div>
        {:else}
            <div class="queue">
                {#each activeItems as item (item.id)}
                    <button class:selected={selectedId === item.id} class="queue-item" type="button" onclick={() => selectSubmission(item)}>
                        <span><b>#{item.id}</b> · {kindLabel(item)}</span>
                        <small>@{item.submittedUsername ?? '—'} · {item.revisionCount} {t.versions}{#if mode === 'history'} · {formatDate(item.reviewedAt)}{/if}</small>
                    </button>
                {/each}
            </div>
        {/if}

        {#if mode === 'history' && historyTotal > HISTORY_PAGE_SIZE}
            <nav class="pagination" aria-label={`${t.page} ${historyPage}`}>
                <button type="button" onclick={() => goHistoryPage(historyPage - 1)} disabled={loading || historyPage <= 1}>‹</button>
                {#each visibleHistoryPages() as page}
                    <button class:active={page === historyPage} type="button" onclick={() => goHistoryPage(page)} disabled={loading}>{page}</button>
                {/each}
                <button type="button" onclick={() => goHistoryPage(historyPage + 1)} disabled={loading || historyPage >= historyPageCount}>›</button>
            </nav>
        {/if}

        {#if selected}
            <article class="review-card">
                <div class="meta-grid">
                    <span>{t.submittedBy}<strong>@{selected.submittedUsername ?? '—'}</strong></span>
                    <span>{t.marker}<strong>{selected.markerId ? `#${selected.markerId}` : t.newMarker}</strong></span>
                    {#if selected.status !== 'pending'}
                        <span>{t.reviewedBy}<strong>@{selected.reviewedUsername ?? '—'}</strong></span>
                        <span>{t.reviewedAt}<strong>{formatDate(selected.reviewedAt)}</strong></span>
                    {/if}
                </div>

                {#if selected.status === 'pending'}
                    <div class="review-editor-heading">
                        <div><strong>{t.fullReview}</strong><small>{t.editedBeforeApproval}</small></div>
                    </div>

                    <div class="form-grid two">
                        <label class:invalid={Boolean(fieldErrors.layer)}>
                            <span>{t.layer} *</span>
                            <select bind:value={reviewMapLayer} disabled={working}>{#each sortedLayers as layer}<option value={layer.id}>{localisedLabel(layer)}</option>{/each}</select>
                            {#if fieldErrors.layer}<small class="field-error">{fieldErrors.layer}</small>{/if}
                        </label>
                        <label>
                            <span>{t.type}</span>
                            <select bind:value={reviewCategoryGroupId} onchange={handleCategoryGroupChange} disabled={working}>{#each sortedGroups as group}<option value={group.id}>{localisedLabel(group)}</option>{/each}</select>
                        </label>
                    </div>

                    <label class:invalid={Boolean(fieldErrors.category)}>
                        <span>{t.category} *</span>
                        <select bind:value={reviewCategoryId} disabled={working}><option value="">{t.chooseCategory}</option>{#each filteredCategories as category}<option value={category.id}>{localisedLabel(category)}</option>{/each}</select>
                        {#if fieldErrors.category}<small class="field-error">{fieldErrors.category}</small>{/if}
                    </label>

                    <fieldset class="location-box">
                        <legend>{t.coordinates} *</legend>
                        <div class="coordinate-row">
                            <span>X *</span><CoordinateStepper axis="x" bind:value={reviewCoordinateX} invalid={Boolean(fieldErrors.coordinateX)} disabled={working} />
                            {#if fieldErrors.coordinateX}<small class="field-error">{fieldErrors.coordinateX}</small>{/if}
                        </div>
                        <div class="coordinate-row">
                            <span>Y *</span><CoordinateStepper axis="y" bind:value={reviewCoordinateY} invalid={Boolean(fieldErrors.coordinateY)} disabled={working} />
                            {#if fieldErrors.coordinateY}<small class="field-error">{fieldErrors.coordinateY}</small>{/if}
                        </div>
                        <button class:active={positionModeActive} class="position-button" type="button" onclick={togglePositionMode} disabled={working}>{positionModeActive ? t.choosingPosition : t.choosePosition}</button>
                    </fieldset>

                    <div class="form-grid two">
                        <label class:invalid={Boolean(fieldErrors.titleEn)}><span>{t.titleEn} *</span><input bind:value={reviewTitleEn} disabled={working} />{#if fieldErrors.titleEn}<small class="field-error">{fieldErrors.titleEn}</small>{/if}</label>
                        <label><span>{t.titlePt} ({t.optional})</span><input bind:value={reviewTitlePt} disabled={working} /></label>
                    </div>
                    <label><span>{t.region} ({t.optional})</span><input bind:value={reviewRegionId} disabled={working} /></label>
                    <label><span>{t.descriptionEn} ({t.optional})</span><textarea rows="3" bind:value={reviewDescriptionEn} disabled={working}></textarea></label>
                    <label><span>{t.descriptionPt} ({t.optional})</span><textarea rows="3" bind:value={reviewDescriptionPt} disabled={working}></textarea></label>
                    <label class:invalid={Boolean(fieldErrors.video)}><span>{t.video} ({t.optional})</span><input type="url" bind:value={reviewVideoUrl} disabled={working} />{#if fieldErrors.video}<small class="field-error">{fieldErrors.video}</small>{/if}</label>

                    {#if selected.correctionKind === 'image' || selected.type === 'create' || selected.payload?.image_url}
                        <div class="form-grid two image-review-grid">
                            <label><span>{t.imageAction}</span><select bind:value={reviewImageAction} disabled={working}><option value="add">{t.addImage}</option><option value="report">{t.reportImage}</option></select></label>
                            {#if reviewImageAction === 'report'}
                                <label><span>{t.targetImage}</span><input bind:value={reviewTargetImageId} disabled={working} /></label>
                            {:else}
                                <label class:invalid={Boolean(fieldErrors.image)}><span>{t.imageUrl} ({t.optional})</span><input type="url" bind:value={reviewImageUrl} disabled={working} />{#if fieldErrors.image}<small class="field-error">{fieldErrors.image}</small>{/if}</label>
                            {/if}
                        </div>
                    {/if}

                    <MarkerContentEditor {language} bind:value={reviewContentItems} disabled={working} />

                    {#if selected.note}<p class="contributor-note"><b>{t.note}:</b> {selected.note}</p>{/if}
                    <label><span>{t.reviewNote} ({t.optional})</span><textarea rows="2" bind:value={reviewNote} disabled={working}></textarea></label>

                    <div class="actions sticky-actions">
                        <button class="approve" type="button" onclick={() => review('approved')} disabled={working}>{working ? t.approving : t.approve}</button>
                        <button class="reject" type="button" onclick={() => review('rejected')} disabled={working}>{t.reject}</button>
                    </div>
                {:else}
                    <div class="proposal">
                        <strong>{t.changes}</strong>
                        {#if selected.payload?.category_id}<p>{t.category}: {localisedCategory(selected.payload.category_id)}</p>{/if}
                        {#if selected.payload?.region_id}<p>{t.region}: {selected.payload.region_id}</p>{/if}
                        {#if selected.payload?.title_en}<p>EN: {selected.payload.title_en}</p>{/if}
                        {#if selected.payload?.title_pt}<p>PT: {selected.payload.title_pt}</p>{/if}
                        {#if selected.payload?.description_en}<p>{selected.payload.description_en}</p>{/if}
                        {#if selected.payload?.description_pt}<p>{selected.payload.description_pt}</p>{/if}
                        {#if selected.payload?.coordinate_x != null && selected.payload?.coordinate_y != null}<p>{t.coordinates}: X {selected.payload.coordinate_x} · Y {selected.payload.coordinate_y}</p>{/if}
                        {#if selected.payload?.content_items?.length}
                            <div class="proposal-content"><b>{t.content}</b>{#each selected.payload.content_items as contentItem}<p><span>{contentTypeLabel(contentItem.type, language)}:</span> {contentItem[`text_${language}`] || contentItem.text_en || contentItem.text_pt || '—'}</p>{/each}</div>
                        {/if}
                    </div>
                    {#if selected.note}<p class="contributor-note"><b>{t.note}:</b> {selected.note}</p>{/if}
                    {#if selected.reviewNote}<p class="review-note"><b>{t.reviewNote}:</b> {selected.reviewNote}</p>{/if}
                {/if}
            </article>
        {/if}
    </section>
{/if}

<style>
    .moderation-panel{display:grid;gap:11px;padding:14px;border:1px solid rgba(200,163,85,.7);border-radius:9px;background:rgba(16,16,20,.98);color:#eee;box-shadow:0 10px 34px rgba(0,0,0,.62);overflow-x:hidden;touch-action:pan-y;overscroll-behavior:contain}
    .panel-heading{display:flex;align-items:center;justify-content:space-between;gap:10px}.panel-heading>div:first-child{display:grid;gap:2px}.heading-actions{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}.eyebrow{color:#c8a355;font-size:.7rem;font-weight:800;text-transform:uppercase}.small-button,.queue-item,.actions button,.history-tabs button,.pagination button,.position-button{border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd;cursor:pointer}.small-button{padding:7px 10px}.history-button{border-color:#66593b;color:#d8b86f}.history-tabs{display:grid;grid-template-columns:1fr 1fr;gap:6px}.history-tabs button{padding:8px 10px;font-weight:800}.history-tabs button.active,.pagination button.active,.position-button.active{border-color:#c8a355;background:#211d14;color:#f1d58e}.queue{display:grid;gap:7px}.queue-item{display:grid;gap:3px;padding:9px;text-align:left}.queue-item small{color:#999}.queue-item.selected{border-color:#c8a355;background:#211d14}.review-card{display:grid;gap:10px;padding:11px;border:1px solid #34343e;border-radius:10px;background:#101014;min-width:0}.meta-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.meta-grid span{display:grid;color:#999;font-size:.72rem}.meta-grid strong{color:#eee;font-size:.82rem}.review-editor-heading{padding-bottom:8px;border-bottom:1px solid #2c2c34}.review-editor-heading>div{display:grid;gap:3px}.review-editor-heading strong{color:#d8b86f}.review-editor-heading small{color:#8f8f98;font-size:.7rem}
    .form-grid{display:grid;gap:9px}.form-grid.two{grid-template-columns:1fr 1fr}label{display:grid;gap:5px;min-width:0}label span,legend{color:#aaa;font-size:.72rem;font-weight:700}input,select,textarea{width:100%;min-width:0;box-sizing:border-box;padding:8px;border:1px solid #34343e;border-radius:8px;background:#0e0e12;color:#eee;font:inherit}textarea{resize:vertical}input:focus,select:focus,textarea:focus{outline:none;border-color:#c8a355;box-shadow:0 0 0 2px rgba(200,163,85,.1)}label.invalid input,label.invalid select,label.invalid textarea{border-color:#c85f67}.field-error{color:#ff9da7;font-size:.67rem}.location-box{margin:0;padding:9px;border:1px solid #303039;border-radius:9px;background:#0b0b0e}.coordinate-row{display:grid;grid-template-columns:36px minmax(0,1fr);align-items:center;gap:7px;margin:7px 0}.coordinate-row>.field-error{grid-column:2}.position-button{padding:8px 10px;margin-top:3px}
    .proposal{padding:9px;border:1px solid #2f2f38;border-radius:8px;background:#0b0b0e}.proposal>strong{color:#c8a355;font-size:.72rem}.proposal p{margin:5px 0;color:#c1c1c8;font-size:.78rem;line-height:1.35}.proposal-content{margin-top:8px;padding-top:8px;border-top:1px solid #292930}.proposal-content>b{color:#aaaab3;font-size:.7rem}.proposal-content p span{color:#d8b86f;font-weight:800}.contributor-note,.review-note{margin:0;color:#c7c7ce;font-size:.8rem}.actions{display:flex;gap:8px;flex-wrap:wrap}.actions button{padding:9px 12px}.actions .approve{border-color:#c8a355;background:#c8a355;color:#111;font-weight:800}.actions .reject{border-color:#704047;color:#ffc0c8}.message{padding:8px;border-radius:8px;font-size:.78rem}.message.error{background:#2b1519;color:#ffc0c8}.message.success{background:#15251a;color:#bcebc7}.loading-card,.empty-state{min-height:116px;display:grid;place-items:center;align-content:center;gap:7px;padding:18px;border:1px solid #303039;border-radius:10px;background:linear-gradient(180deg,rgba(20,20,25,.96),rgba(12,12,15,.96));text-align:center}.empty-state strong{color:#e6e6e8}.empty-state p{max-width:290px;margin:0;color:#91919b;font-size:.76rem;line-height:1.4}.empty-icon{width:38px;height:38px;display:grid;place-items:center;border:1px solid rgba(200,163,85,.45);border-radius:50%;background:rgba(200,163,85,.09);color:#d8b86f;font-weight:900}.pagination{display:flex;align-items:center;justify-content:center;gap:5px;flex-wrap:wrap}.pagination button{min-width:32px;height:32px;padding:0 8px}.small-button:disabled,.history-tabs button:disabled,.pagination button:disabled,.actions button:disabled,.position-button:disabled{opacity:.5;cursor:not-allowed}
    @media(max-width:560px){.meta-grid,.form-grid.two{grid-template-columns:1fr}.panel-heading{align-items:flex-start;flex-direction:column}.heading-actions{width:100%;justify-content:flex-start}.review-card{padding:9px}.sticky-actions{position:sticky;bottom:-11px;z-index:5;margin:4px -11px -11px;padding:10px 11px;background:rgba(16,16,20,.99);border-top:1px solid #2e2e36}.sticky-actions button{flex:1}.image-review-grid{grid-template-columns:1fr!important}}
</style>
