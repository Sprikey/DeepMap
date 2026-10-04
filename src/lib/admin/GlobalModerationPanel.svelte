<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { normaliseHttpUrl } from '$lib/map/media.js';
    import { loadDeepMapGameData } from '$lib/map/map-data.js';
    import { deepMapGames, getDeepMapGameFallback, getDeepMapGameMapHref, getDeepMapGameName } from '$lib/games/registry.js';
    import CoordinateStepper from '$lib/editor/CoordinateStepper.svelte';
    import MarkerContentEditor from '$lib/editor/MarkerContentEditor.svelte';
    import { contentTypeLabel, serialiseMarkerContentItems } from '$lib/editor/marker-content.js';
    import { loadMarkerSubmissionsPage, reviewMarkerSubmission } from '$lib/community/marker-contributions.js';

    let { language = 'en', active = true } = $props();

    const PENDING_PAGE_SIZE = 20;
    const HISTORY_PAGE_SIZE = 10;

    const TEXT = {
        en: {
            title: 'Global moderation', pending: 'Pending', history: 'History', approved: 'Approved', rejected: 'Rejected',
            refresh: 'Refresh', allMaps: 'All maps', map: 'Map', noPending: 'No pending submissions.', noHistory: 'No submissions in this history.',
            page: 'Page', submittedBy: 'Submitted by', reviewedBy: 'Reviewed by', reviewedAt: 'Reviewed', marker: 'Marker',
            newMarker: 'New marker', correction: 'Correction', versions: 'versions', review: 'Review / edit submission',
            reviewHelp: 'You can correct the submitted data before approving it.', layer: 'Map layer', type: 'Type', category: 'Category',
            chooseCategory: 'Choose a category…', coordinates: 'Coordinates', titleEn: 'Title — EN', titlePt: 'Title — PT', region: 'Region',
            descriptionEn: 'Description — EN', descriptionPt: 'Description — PT', video: 'Video URL', optional: 'optional', required: 'Required field.',
            requiredSummary: 'Check the highlighted required fields.', invalidUrl: 'Use a valid http(s) URL.', imageAction: 'Image action', imageUrl: 'Image URL',
            addImage: 'Add image', reportImage: 'Report existing image', targetImage: 'Image ID', note: 'Contributor note', moderatorNote: 'Moderator note',
            approve: 'Approve', reject: 'Reject', close: 'Close', working: 'Working…', approvedOk: 'Submission approved.', rejectedOk: 'Submission rejected.',
            loadError: 'Could not load moderation queue.', reviewError: 'Could not review this submission.', openMap: 'Open on map', content: 'Additional content',
            changes: 'Submitted data', gameUnavailable: 'This game is not registered in the admin registry yet.'
        },
        pt: {
            title: 'Moderação global', pending: 'Pendentes', history: 'Histórico', approved: 'Aprovados', rejected: 'Reprovados',
            refresh: 'Atualizar', allMaps: 'Todos os mapas', map: 'Mapa', noPending: 'Sem submissões pendentes.', noHistory: 'Ainda não existem submissões neste histórico.',
            page: 'Página', submittedBy: 'Enviado por', reviewedBy: 'Revisto por', reviewedAt: 'Revisto', marker: 'Marcador',
            newMarker: 'Novo marcador', correction: 'Correção', versions: 'versões', review: 'Rever / editar submissão',
            reviewHelp: 'Podes corrigir os dados submetidos antes de aprovar.', layer: 'Camada do mapa', type: 'Tipo', category: 'Categoria',
            chooseCategory: 'Escolhe uma categoria…', coordinates: 'Coordenadas', titleEn: 'Título — EN', titlePt: 'Título — PT', region: 'Região',
            descriptionEn: 'Descrição — EN', descriptionPt: 'Descrição — PT', video: 'URL do vídeo', optional: 'opcional', required: 'Campo obrigatório.',
            requiredSummary: 'Revê os campos obrigatórios assinalados.', invalidUrl: 'Usa um URL http(s) válido.', imageAction: 'Ação da imagem', imageUrl: 'URL da imagem',
            addImage: 'Adicionar imagem', reportImage: 'Reportar imagem existente', targetImage: 'ID da imagem', note: 'Nota do utilizador', moderatorNote: 'Nota da moderação',
            approve: 'Aprovar', reject: 'Rejeitar', close: 'Fechar', working: 'A processar…', approvedOk: 'Submissão aprovada.', rejectedOk: 'Submissão reprovada.',
            loadError: 'Não foi possível carregar a fila de moderação.', reviewError: 'Não foi possível rever esta submissão.', openMap: 'Abrir no mapa', content: 'Conteúdo adicional',
            changes: 'Dados submetidos', gameUnavailable: 'Este jogo ainda não está registado no painel de administração.'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let mode = $state('pending');
    let historyStatus = $state('approved');
    let gameFilter = $state('all');
    let page = $state(1);
    let items = $state([]);
    let total = $state(0);
    let selectedId = $state(null);
    let loading = $state(false);
    let working = $state(false);
    let errorMessage = $state('');
    let successMessage = $state('');
    let loadedOnce = false;

    let categories = $state({});
    let categoryGroups = $state([]);
    let mapDefinitions = $state({});
    let locations = $state([]);
    let contextGameId = $state(null);
    const contextCache = new Map();

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
    let reviewNote = $state('');
    let fieldErrors = $state({});

    let selected = $derived(selectedId == null ? null : items.find((item) => item.id === selectedId) ?? null);
    let pageSize = $derived(mode === 'history' ? HISTORY_PAGE_SIZE : PENDING_PAGE_SIZE);
    let pageCount = $derived(Math.max(1, Math.ceil(total / pageSize)));
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

    function formatDate(value) {
        if (!value) return '—';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '—';
        return new Intl.DateTimeFormat(language === 'pt' ? 'pt-PT' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
    }

    function visiblePages() {
        const maxVisible = 5;
        let start = Math.max(1, page - Math.floor(maxVisible / 2));
        let end = Math.min(pageCount, start + maxVisible - 1);
        start = Math.max(1, end - maxVisible + 1);
        return Array.from({ length: end - start + 1 }, (_, index) => start + index);
    }

    function reviewItemsFrom(source = []) {
        return (Array.isArray(source) ? source : []).map((item) => ({
            type: item?.type ?? 'note',
            textEn: item?.textEn ?? item?.text_en ?? item?.text?.en ?? '',
            textPt: item?.textPt ?? item?.text_pt ?? item?.text?.pt ?? ''
        }));
    }

    async function ensureGameContext(gameId) {
        if (!gameId) return false;
        if (contextCache.has(gameId)) {
            const cached = contextCache.get(gameId);
            categories = cached.categories;
            categoryGroups = cached.categoryGroups;
            mapDefinitions = cached.mapDefinitions;
            locations = cached.locations;
            contextGameId = gameId;
            return true;
        }

        const registered = deepMapGames.some((game) => game.id === gameId);
        if (!registered) {
            categories = {};
            categoryGroups = [];
            mapDefinitions = {};
            locations = [];
            contextGameId = gameId;
            return false;
        }

        const data = await loadDeepMapGameData({
            supabase: getSupabaseBrowserClient(),
            gameId,
            fallback: getDeepMapGameFallback(gameId)
        });
        const context = {
            categories: data.categories ?? {},
            categoryGroups: data.categoryGroups ?? [],
            mapDefinitions: data.mapDefinitions ?? {},
            locations: data.locations ?? []
        };
        contextCache.set(gameId, context);
        categories = context.categories;
        categoryGroups = context.categoryGroups;
        mapDefinitions = context.mapDefinitions;
        locations = context.locations;
        contextGameId = gameId;
        return true;
    }

    function targetLocation(item) {
        if (!item?.markerId || contextGameId !== item.gameId) return null;
        return locations.find((location) => Number(location.databaseId) === Number(item.markerId)) ?? null;
    }

    function payloadValue(payload, key, fallback = '') {
        if (payload && Object.prototype.hasOwnProperty.call(payload, key)) return payload[key] ?? '';
        return fallback ?? '';
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
        reviewContentItems = reviewItemsFrom(payload.content_items ?? target?.contentItems ?? []);
        reviewImageUrl = String(payload.image_url ?? '');
        reviewImageAction = payload.image_action ?? 'add';
        reviewTargetImageId = payload.target_image_id == null ? '' : String(payload.target_image_id);
        reviewNote = item.status === 'pending' ? '' : (item.reviewNote ?? '');
        fieldErrors = {};
    }

    function hasCoordinateValue(value) {
        return String(value ?? '').trim() !== '' && Number.isFinite(Number(value));
    }

    function validateReview() {
        const errors = {};
        if (!reviewMapLayer) errors.layer = t.required;
        if (!reviewCategoryId) errors.category = t.required;
        if (!reviewTitleEn.trim()) errors.titleEn = t.required;
        if (!hasCoordinateValue(reviewCoordinateX)) errors.coordinateX = t.required;
        if (!hasCoordinateValue(reviewCoordinateY)) errors.coordinateY = t.required;
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

    function mapHref(item = selected) {
        if (!item) return '#';
        const base = getDeepMapGameMapHref(item.gameId);
        const payload = item.payload ?? {};
        const x = Number(payload.coordinate_x ?? reviewCoordinateX);
        const y = Number(payload.coordinate_y ?? reviewCoordinateY);
        const hasSubmittedCoordinates = Number.isFinite(x) && Number.isFinite(y)
            && (payload.coordinate_x != null || payload.coordinate_y != null || item.type === 'create');

        if (!hasSubmittedCoordinates && item.markerId) {
            return `${base}?marker=${encodeURIComponent(item.markerId)}`;
        }

        const layer = payload.map_layer ?? reviewMapLayer ?? 'surface';
        const category = payload.category_id ?? reviewCategoryId ?? '';
        const params = new URLSearchParams();
        if (Number.isFinite(x) && Number.isFinite(y)) {
            params.set('reviewX', String(x));
            params.set('reviewY', String(y));
            params.set('layer', String(layer));
            if (category) params.set('category', String(category));
        }
        if (item.markerId) params.set('marker', String(item.markerId));
        params.set('submission', String(item.id));
        return `${base}?${params.toString()}`;
    }

    async function load() {
        if (!active || loading) return;
        loading = true;
        errorMessage = '';
        successMessage = '';
        try {
            const result = await loadMarkerSubmissionsPage({
                supabase: getSupabaseBrowserClient(),
                gameId: gameFilter === 'all' ? null : gameFilter,
                status: mode === 'pending' ? 'pending' : historyStatus,
                limit: pageSize,
                offset: (page - 1) * pageSize
            });
            items = result.items;
            total = result.total;
            if (selectedId !== null && !items.some((item) => item.id === selectedId)) selectedId = null;
            if (page > pageCount) page = pageCount;
        } catch (error) {
            console.error('DeepMap global moderation:', error);
            items = [];
            total = 0;
            errorMessage = t.loadError;
        } finally {
            loading = false;
        }
    }

    async function selectSubmission(item) {
        if (selectedId === item.id) {
            selectedId = null;
            fieldErrors = {};
            return;
        }
        loading = true;
        errorMessage = '';
        successMessage = '';
        try {
            const registered = await ensureGameContext(item.gameId);
            selectedId = item.id;
            populateReviewForm(item);
            if (!registered) errorMessage = t.gameUnavailable;
        } catch (error) {
            console.error('DeepMap moderation game context:', error);
            errorMessage = t.loadError;
        } finally {
            loading = false;
        }
    }

    async function review(decision) {
        if (!selected || selected.status !== 'pending' || working) return;
        if (decision === 'approved' && !validateReview()) {
            errorMessage = t.requiredSummary;
            return;
        }
        working = true;
        errorMessage = '';
        successMessage = '';
        try {
            await reviewMarkerSubmission({
                supabase: getSupabaseBrowserClient(),
                submissionId: selected.id,
                decision,
                reviewNote,
                payloadOverride: decision === 'approved' ? buildReviewPayload() : null
            });
            successMessage = decision === 'approved' ? t.approvedOk : t.rejectedOk;
            selectedId = null;
            await load();
        } catch (error) {
            console.error('DeepMap global moderation review:', error);
            errorMessage = t.reviewError;
        } finally {
            working = false;
        }
    }

    async function setMode(nextMode) {
        if (mode === nextMode) return;
        mode = nextMode;
        page = 1;
        selectedId = null;
        await load();
    }

    async function setHistoryStatus(status) {
        if (historyStatus === status && mode === 'history') return;
        historyStatus = status;
        mode = 'history';
        page = 1;
        selectedId = null;
        await load();
    }

    async function setGameFilter(event) {
        gameFilter = event.currentTarget.value;
        page = 1;
        selectedId = null;
        await load();
    }

    async function goPage(nextPage) {
        if (nextPage < 1 || nextPage > pageCount || nextPage === page) return;
        page = nextPage;
        selectedId = null;
        await load();
    }

    function handleCategoryGroupChange() {
        if (reviewCategoryId && categories[reviewCategoryId]?.group !== reviewCategoryGroupId) reviewCategoryId = '';
        fieldErrors = { ...fieldErrors, category: undefined };
    }

    $effect(() => {
        if (!active || loadedOnce) return;
        loadedOnce = true;
        void load();
    });
</script>

{#if active}
<section class="global-moderation" aria-label={t.title}>
    <div class="toolbar">
        <div>
            <span class="eyebrow">DeepMap</span>
            <h2>{t.title}</h2>
        </div>
        <div class="toolbar-actions">
            <label class="map-filter"><span>{t.map}</span><select value={gameFilter} onchange={setGameFilter}><option value="all">{t.allMaps}</option>{#each deepMapGames as game}<option value={game.id}>{game.name}</option>{/each}</select></label>
            <button type="button" onclick={load} disabled={loading || working}>{t.refresh}</button>
        </div>
    </div>

    <div class="mode-tabs" role="tablist">
        <button class:active={mode === 'pending'} type="button" onclick={() => setMode('pending')}>{t.pending}</button>
        <button class:active={mode === 'history' && historyStatus === 'approved'} type="button" onclick={() => setHistoryStatus('approved')}>{t.approved}</button>
        <button class:active={mode === 'history' && historyStatus === 'rejected'} type="button" onclick={() => setHistoryStatus('rejected')}>{t.rejected}</button>
    </div>

    {#if errorMessage}<p class="message error" role="alert">{errorMessage}</p>{/if}
    {#if successMessage}<p class="message success" role="status">{successMessage}</p>{/if}

    <div class="moderation-layout">
        <div class="queue-column">
            {#if loading && !items.length}
                <div class="empty">…</div>
            {:else if !items.length}
                <div class="empty"><strong>{mode === 'pending' ? t.noPending : t.noHistory}</strong></div>
            {:else}
                <div class="queue">
                    {#each items as item (item.id)}
                        <button class:selected={selectedId === item.id} type="button" onclick={() => selectSubmission(item)}>
                            <span class="queue-top"><b>{getDeepMapGameName(item.gameId)}</b><em>#{item.id}</em></span>
                            <strong>{item.type === 'create' ? t.newMarker : t.correction}</strong>
                            <small>@{item.submittedUsername ?? '—'} · {item.revisionCount} {t.versions}{#if item.status !== 'pending'} · {formatDate(item.reviewedAt)}{/if}</small>
                        </button>
                    {/each}
                </div>
            {/if}

            {#if total > pageSize}
                <nav class="pagination" aria-label={`${t.page} ${page}`}>
                    <button type="button" onclick={() => goPage(page - 1)} disabled={loading || page <= 1}>‹</button>
                    {#each visiblePages() as p}<button class:active={p === page} type="button" onclick={() => goPage(p)} disabled={loading}>{p}</button>{/each}
                    <button type="button" onclick={() => goPage(page + 1)} disabled={loading || page >= pageCount}>›</button>
                </nav>
            {/if}
        </div>

        <div class="review-column">
            {#if selected}
                <article class="review-card">
                    <div class="review-head">
                        <div>
                            <span class="eyebrow">{getDeepMapGameName(selected.gameId)}</span>
                            <h3>#{selected.id} · {selected.type === 'create' ? t.newMarker : t.correction}</h3>
                        </div>
                        <div class="review-head-actions"><a href={mapHref(selected)} target="_blank" rel="noreferrer">{t.openMap}</a><button type="button" onclick={() => { selectedId = null; }}>{t.close}</button></div>
                    </div>

                    <div class="meta-grid">
                        <span>{t.submittedBy}<strong>@{selected.submittedUsername ?? '—'}</strong></span>
                        <span>{t.marker}<strong>{selected.markerId ? `#${selected.markerId}` : t.newMarker}</strong></span>
                        {#if selected.status !== 'pending'}
                            <span>{t.reviewedBy}<strong>@{selected.reviewedUsername ?? '—'}</strong></span>
                            <span>{t.reviewedAt}<strong>{formatDate(selected.reviewedAt)}</strong></span>
                        {/if}
                    </div>

                    {#if selected.status === 'pending'}
                        <div class="review-intro"><strong>{t.review}</strong><small>{t.reviewHelp}</small></div>
                        <div class="form-grid two">
                            <label class:invalid={Boolean(fieldErrors.layer)}><span>{t.layer} *</span><select bind:value={reviewMapLayer} disabled={working}>{#each sortedLayers as layer}<option value={layer.id}>{localisedLabel(layer)}</option>{/each}</select>{#if fieldErrors.layer}<small class="field-error">{fieldErrors.layer}</small>{/if}</label>
                            <label><span>{t.type}</span><select bind:value={reviewCategoryGroupId} onchange={handleCategoryGroupChange} disabled={working}>{#each sortedGroups as group}<option value={group.id}>{localisedLabel(group)}</option>{/each}</select></label>
                        </div>
                        <label class:invalid={Boolean(fieldErrors.category)}><span>{t.category} *</span><select bind:value={reviewCategoryId} disabled={working}><option value="">{t.chooseCategory}</option>{#each filteredCategories as category}<option value={category.id}>{localisedLabel(category)}</option>{/each}</select>{#if fieldErrors.category}<small class="field-error">{fieldErrors.category}</small>{/if}</label>
                        <fieldset class="location-box"><legend>{t.coordinates} *</legend><div class="coordinate-row"><span>X *</span><CoordinateStepper axis="x" bind:value={reviewCoordinateX} invalid={Boolean(fieldErrors.coordinateX)} disabled={working} />{#if fieldErrors.coordinateX}<small class="field-error">{fieldErrors.coordinateX}</small>{/if}</div><div class="coordinate-row"><span>Y *</span><CoordinateStepper axis="y" bind:value={reviewCoordinateY} invalid={Boolean(fieldErrors.coordinateY)} disabled={working} />{#if fieldErrors.coordinateY}<small class="field-error">{fieldErrors.coordinateY}</small>{/if}</div></fieldset>
                        <div class="form-grid two"><label class:invalid={Boolean(fieldErrors.titleEn)}><span>{t.titleEn} *</span><input bind:value={reviewTitleEn} disabled={working} />{#if fieldErrors.titleEn}<small class="field-error">{fieldErrors.titleEn}</small>{/if}</label><label><span>{t.titlePt} ({t.optional})</span><input bind:value={reviewTitlePt} disabled={working} /></label></div>
                        <label><span>{t.region} ({t.optional})</span><input bind:value={reviewRegionId} disabled={working} /></label>
                        <label><span>{t.descriptionEn} ({t.optional})</span><textarea rows="3" bind:value={reviewDescriptionEn} disabled={working}></textarea></label>
                        <label><span>{t.descriptionPt} ({t.optional})</span><textarea rows="3" bind:value={reviewDescriptionPt} disabled={working}></textarea></label>
                        <label class:invalid={Boolean(fieldErrors.video)}><span>{t.video} ({t.optional})</span><input type="url" bind:value={reviewVideoUrl} disabled={working} />{#if fieldErrors.video}<small class="field-error">{fieldErrors.video}</small>{/if}</label>

                        {#if selected.correctionKind === 'image' || selected.type === 'create' || selected.payload?.image_url}
                            <div class="form-grid two"><label><span>{t.imageAction}</span><select bind:value={reviewImageAction} disabled={working}><option value="add">{t.addImage}</option><option value="report">{t.reportImage}</option></select></label>{#if reviewImageAction === 'report'}<label><span>{t.targetImage}</span><input bind:value={reviewTargetImageId} disabled={working} /></label>{:else}<label class:invalid={Boolean(fieldErrors.image)}><span>{t.imageUrl} ({t.optional})</span><input type="url" bind:value={reviewImageUrl} disabled={working} />{#if fieldErrors.image}<small class="field-error">{fieldErrors.image}</small>{/if}</label>{/if}</div>
                        {/if}

                        <MarkerContentEditor {language} bind:value={reviewContentItems} disabled={working} />
                        {#if selected.note}<p class="note"><b>{t.note}:</b> {selected.note}</p>{/if}
                        <label><span>{t.moderatorNote} ({t.optional})</span><textarea rows="2" bind:value={reviewNote} disabled={working}></textarea></label>
                        <div class="actions"><button class="approve" type="button" onclick={() => review('approved')} disabled={working}>{working ? t.working : t.approve}</button><button class="reject" type="button" onclick={() => review('rejected')} disabled={working}>{t.reject}</button><button type="button" onclick={() => { selectedId = null; }} disabled={working}>{t.close}</button></div>
                    {:else}
                        <div class="proposal"><strong>{t.changes}</strong>{#if selected.payload?.category_id}<p>{t.category}: {localisedCategory(selected.payload.category_id)}</p>{/if}{#if selected.payload?.title_en}<p>EN: {selected.payload.title_en}</p>{/if}{#if selected.payload?.title_pt}<p>PT: {selected.payload.title_pt}</p>{/if}{#if selected.payload?.coordinate_x != null && selected.payload?.coordinate_y != null}<p>{t.coordinates}: X {selected.payload.coordinate_x} · Y {selected.payload.coordinate_y}</p>{/if}{#if selected.payload?.content_items?.length}<div><b>{t.content}</b>{#each selected.payload.content_items as contentItem}<p><span>{contentTypeLabel(contentItem.type, language)}:</span> {contentItem[`text_${language}`] || contentItem.text_en || contentItem.text_pt || '—'}</p>{/each}</div>{/if}</div>
                        {#if selected.note}<p class="note"><b>{t.note}:</b> {selected.note}</p>{/if}
                        {#if selected.reviewNote}<p class="note"><b>{t.moderatorNote}:</b> {selected.reviewNote}</p>{/if}
                    {/if}
                </article>
            {:else}
                <div class="review-placeholder"><strong>{mode === 'pending' ? t.pending : t.history}</strong><p>{language === 'pt' ? 'Seleciona uma submissão para a rever.' : 'Select a submission to review it.'}</p></div>
            {/if}
        </div>
    </div>
</section>
{/if}

<style>
    .global-moderation{display:grid;gap:16px;color:#eee}.toolbar{display:flex;align-items:flex-end;justify-content:space-between;gap:14px}.toolbar h2{margin:2px 0 0;font-size:1.35rem}.eyebrow{color:#c8a355;font-size:.68rem;font-weight:900;text-transform:uppercase;letter-spacing:.08em}.toolbar-actions{display:flex;align-items:flex-end;gap:8px;flex-wrap:wrap}.toolbar button,.toolbar select,.mode-tabs button,.pagination button,.review-head-actions button,.review-head-actions a,.actions button{border:1px solid #3b3b45;border-radius:8px;background:#17171c;color:#ddd;cursor:pointer;text-decoration:none}.toolbar button{padding:9px 12px}.map-filter{display:grid;gap:4px}.map-filter span{font-size:.68rem;color:#999}.map-filter select{min-width:170px;padding:8px;background:#111116;color:#eee}.mode-tabs{display:flex;gap:7px;flex-wrap:wrap}.mode-tabs button{padding:8px 12px;font-weight:800}.mode-tabs button.active,.pagination button.active{border-color:#c8a355;background:#211d14;color:#f0d28a}.moderation-layout{display:grid;grid-template-columns:minmax(260px,360px) minmax(0,1fr);gap:14px;align-items:start}.queue-column,.review-column{min-width:0}.queue{display:grid;gap:7px}.queue>button{display:grid;gap:4px;padding:10px;border:1px solid #303039;border-radius:9px;background:#111115;color:#ddd;text-align:left;cursor:pointer}.queue>button:hover,.queue>button.selected{border-color:#c8a355;background:#1d1a13}.queue-top{display:flex;align-items:center;justify-content:space-between;gap:8px}.queue-top b{color:#d8b86f;font-size:.72rem}.queue-top em{color:#73737d;font-size:.66rem;font-style:normal}.queue small{color:#9696a0}.pagination{display:flex;gap:5px;justify-content:center;flex-wrap:wrap;margin-top:10px}.pagination button{min-width:32px;height:32px}.review-card,.review-placeholder,.empty{border:1px solid #303039;border-radius:12px;background:#101014}.review-card{display:grid;gap:12px;padding:14px}.review-placeholder,.empty{min-height:150px;display:grid;place-items:center;align-content:center;gap:6px;padding:18px;color:#92929c;text-align:center}.review-placeholder strong,.empty strong{color:#e4e4e7}.review-placeholder p{margin:0}.review-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}.review-head h3{margin:3px 0 0}.review-head-actions{display:flex;gap:6px;flex-wrap:wrap}.review-head-actions a,.review-head-actions button{padding:7px 9px;font-size:.72rem}.review-head-actions a{border-color:#66593b;color:#d8b86f}.meta-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}.meta-grid span{display:grid;color:#8f8f98;font-size:.68rem}.meta-grid strong{color:#eee;font-size:.78rem}.review-intro{display:grid;gap:3px;padding-top:9px;border-top:1px solid #2b2b33}.review-intro strong{color:#d8b86f}.review-intro small{color:#8f8f98}.form-grid{display:grid;gap:9px}.form-grid.two{grid-template-columns:1fr 1fr}label{display:grid;gap:5px}label span,legend{color:#aaa;font-size:.7rem;font-weight:700}input,select,textarea{width:100%;min-width:0;box-sizing:border-box;padding:8px;border:1px solid #34343e;border-radius:8px;background:#0d0d11;color:#eee;font:inherit}textarea{resize:vertical}label.invalid input,label.invalid select,label.invalid textarea{border-color:#c85f67}.field-error{color:#ff9da7;font-size:.66rem}.location-box{margin:0;padding:10px;border:1px solid #303039;border-radius:9px}.coordinate-row{display:grid;grid-template-columns:36px minmax(0,1fr);gap:7px;align-items:center;margin:7px 0}.coordinate-row>.field-error{grid-column:2}.actions{display:flex;gap:8px;flex-wrap:wrap;padding-top:9px;border-top:1px solid #2d2d35;background:#101014}.actions button{padding:9px 12px}.actions .approve{border-color:#c8a355;background:#c8a355;color:#111;font-weight:900}.actions .reject{border-color:#704047;color:#ffc0c8}.note{margin:0;color:#c7c7ce;font-size:.78rem}.proposal{padding:10px;border:1px solid #2f2f38;border-radius:9px;background:#0b0b0e}.proposal>strong{color:#c8a355}.proposal p{margin:5px 0;color:#c1c1c8;font-size:.78rem}.proposal p span{color:#d8b86f;font-weight:800}.message{margin:0;padding:9px;border-radius:8px}.message.error{background:#2b1519;color:#ffc0c8}.message.success{background:#15251a;color:#bcebc7}
    @media(max-width:900px){.moderation-layout{grid-template-columns:1fr}.queue-column{max-height:38vh;overflow:auto;touch-action:pan-y}.review-column{min-height:0}.meta-grid{grid-template-columns:1fr 1fr}}
    @media(max-width:600px){.toolbar{align-items:stretch;flex-direction:column}.toolbar-actions,.map-filter,.map-filter select{width:100%}.toolbar button{flex:1}.mode-tabs{display:grid;grid-template-columns:repeat(3,1fr)}.mode-tabs button{padding:8px 5px}.review-card{padding:10px}.review-head{flex-direction:column}.review-head-actions{width:100%}.review-head-actions a,.review-head-actions button{flex:1;text-align:center}.meta-grid,.form-grid.two{grid-template-columns:1fr}.actions{margin:4px 0 0;padding:10px 0 0}.actions button{flex:1}.queue-column{max-height:32vh}}
</style>
