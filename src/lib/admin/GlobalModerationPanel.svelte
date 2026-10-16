<script>
    import { tick, onMount, untrack } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { normaliseHttpUrl } from '$lib/map/media.js';
    import { getGameRendererBySlug } from '$lib/games/registry.js';
    import { loadModerationGameCatalog } from '$lib/games/game-context.js';
    import { markerIdKey } from '$lib/editor/marker-editor.js';
    import CoordinateStepper from '$lib/editor/CoordinateStepper.svelte';
    import MarkerContentEditor from '$lib/editor/MarkerContentEditor.svelte';
    import { contentTypeLabel, serialiseMarkerContentItems } from '$lib/editor/marker-content.js';
    import { isCommunityGameUuid, loadMarkerSubmissionsPage, loadMarkerReviewContext, reviewMarkerSubmission } from '$lib/community/marker-contributions.js';

    let { language = 'en', active = true } = $props();

    const TEXT = {
        en: {
            title: 'Global moderation', pending: 'Pending', history: 'History', approved: 'Approved', rejected: 'Rejected',
            refresh: 'Refresh', refreshing: 'Refreshing…', refreshed: 'Updated just now ✓', allMaps: 'All maps', map: 'Map', perPage: 'Per page', noPending: 'No pending submissions.', noHistory: 'No submissions in this history.',
            page: 'Page', submittedBy: 'Submitted by', reviewedBy: 'Reviewed by', reviewedAt: 'Reviewed', marker: 'Marker',
            newMarker: 'New marker', correction: 'Correction', versions: 'versions', review: 'Review / edit submission',
            reviewHelp: 'You can correct the submitted data before approving it.', layer: 'Map layer', type: 'Type', category: 'Category',
            chooseCategory: 'Choose a category…', coordinates: 'Coordinates', titleEn: 'Title — EN', titlePt: 'Title — PT', region: 'Region',
            descriptionEn: 'Description — EN', descriptionPt: 'Description — PT', video: 'Video URL', optional: 'optional', required: 'Required field.',
            requiredSummary: 'Check the highlighted required fields.', invalidUrl: 'Use a valid http(s) URL.', imageAction: 'Image action', imageUrl: 'Image URL',
            addImage: 'Add image', reportImage: 'Report existing image', targetImage: 'Image ID', note: 'Contributor note', moderatorNote: 'Moderator note',
            approve: 'Approve', reject: 'Reject', close: 'Close', working: 'Working…', approvedOk: 'Submission approved.', rejectedOk: 'Submission rejected.',
            loadError: 'Could not load moderation queue.', reviewError: 'Could not review this submission.', openMap: 'Open on map', content: 'Additional content',
            optionsError: 'Could not load all review options. Current/submitted choices remain available.',
            changes: 'Submitted data', current: 'Current', suggested: 'Suggested', finalVersion: 'Final version to publish', comparison: 'Change comparison', comparisonHelp: 'Only fields that actually changed are shown.', noStructuredChanges: 'No structured fields changed. Check the contributor note below.', noCurrentMarker: 'The current marker could not be loaded for comparison.', images: 'Images', addImageSummary: 'Add image', reportImageSummary: 'Report image', gameUnavailable: 'This game is not registered in the admin registry yet.', historyDetails: 'Decision details', submittedAt: 'Submitted', decision: 'Decision', viewDetails: 'View details', revisionsHistory: 'Revision history', revision: 'Revision', by: 'by', legacyDetails: 'Full revision details are not available for this older record.'
        },
        pt: {
            title: 'Moderação global', pending: 'Pendentes', history: 'Histórico', approved: 'Aprovados', rejected: 'Reprovados',
            refresh: 'Atualizar', refreshing: 'A atualizar…', refreshed: 'Atualizado agora ✓', allMaps: 'Todos os mapas', map: 'Mapa', perPage: 'Por página', noPending: 'Sem submissões pendentes.', noHistory: 'Ainda não existem submissões neste histórico.',
            page: 'Página', submittedBy: 'Enviado por', reviewedBy: 'Revisto por', reviewedAt: 'Revisto', marker: 'Marcador',
            newMarker: 'Novo marcador', correction: 'Correção', versions: 'versões', review: 'Rever / editar submissão',
            reviewHelp: 'Podes corrigir os dados submetidos antes de aprovar.', layer: 'Camada do mapa', type: 'Tipo', category: 'Categoria',
            chooseCategory: 'Escolhe uma categoria…', coordinates: 'Coordenadas', titleEn: 'Título — EN', titlePt: 'Título — PT', region: 'Região',
            descriptionEn: 'Descrição — EN', descriptionPt: 'Descrição — PT', video: 'URL do vídeo', optional: 'opcional', required: 'Campo obrigatório.',
            requiredSummary: 'Revê os campos obrigatórios assinalados.', invalidUrl: 'Usa um URL http(s) válido.', imageAction: 'Ação da imagem', imageUrl: 'URL da imagem',
            addImage: 'Adicionar imagem', reportImage: 'Reportar imagem existente', targetImage: 'ID da imagem', note: 'Nota do utilizador', moderatorNote: 'Nota da moderação',
            approve: 'Aprovar', reject: 'Rejeitar', close: 'Fechar', working: 'A processar…', approvedOk: 'Submissão aprovada.', rejectedOk: 'Submissão reprovada.',
            loadError: 'Não foi possível carregar a fila de moderação.', reviewError: 'Não foi possível rever esta submissão.', openMap: 'Abrir no mapa', content: 'Conteúdo adicional',
            optionsError: 'Não foi possível carregar todas as opções de revisão. As opções atuais/submetidas continuam disponíveis.',
            changes: 'Dados submetidos', current: 'Atual', suggested: 'Sugerido', finalVersion: 'Versão final a publicar', comparison: 'Comparação da alteração', comparisonHelp: 'São mostrados apenas os campos que realmente mudaram.', noStructuredChanges: 'Não existem campos estruturados alterados. Revê a nota do utilizador abaixo.', noCurrentMarker: 'Não foi possível carregar o marcador atual para comparação.', images: 'Imagens', addImageSummary: 'Adicionar imagem', reportImageSummary: 'Reportar imagem', gameUnavailable: 'Este jogo ainda não está registado no painel de administração.', historyDetails: 'Detalhes da decisão', submittedAt: 'Enviado', decision: 'Decisão', viewDetails: 'Ver detalhes', revisionsHistory: 'Histórico de versões', revision: 'Versão', by: 'por', legacyDetails: 'Os detalhes completos das versões não estão disponíveis para este registo antigo.'
        }
    };

    let languageKey = $derived(/** @type {'en' | 'pt'} */ (String(language ?? '').toLowerCase().startsWith('pt') ? 'pt' : 'en'));
    let t = $derived(TEXT[languageKey] ?? TEXT.en);
    let mode = $state('pending');
    let historyStatus = $state('approved');
    let gameFilter = $state('all');
    let page = $state(1);
    let pendingPageSize = $state(10);
    let historyPageSize = $state(10);
    let items = $state(/** @type {any[]} */ ([]));
    let total = $state(0);
    let selectedId = $state(/** @type {string | null} */ (null));
    let selectionGameUuid = $state(/** @type {string | null} */ (null));
    let loading = $state(false);
    let working = $state(false);
    let errorMessage = $state('');
    let successMessage = $state('');
    let staffUserId = $state(/** @type {string | null} */ (null));
    let gameCatalog = $state(/** @type {Awaited<ReturnType<typeof loadModerationGameCatalog>>} */ ([]));
    let catalogError = $state('');
    let contextLoading = $state(false);
    let optionsLoading = $state(false);
    let optionsError = $state('');
    let reviewContext = $state(/** @type {Awaited<ReturnType<typeof loadMarkerReviewContext>> | null} */ (null));
    let categories = $state(/** @type {Record<string, any>} */ ({}));
    let categoryGroups = $state(/** @type {any[]} */ ([]));
    let mapDefinitions = $state(/** @type {Record<string, any>} */ ({}));
    let queueGeneration = 0;
    let catalogGeneration = 0;
    let selectionGeneration = 0;
    let revisionGeneration = 0;
    let accessGeneration = 0;
    let sessionGeneration = 0;
    let operationGeneration = 0;
    let mounted = false;
    let reviewLayerKey = $state('');
    let reviewCategoryKey = $state('');

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
    let historyRevisions = $state(/** @type {any[]} */ ([]));
    let revisionsError = $state('');
    let historyRevisionsLoading = $state(false);
    let historyRevisionsLoaded = $state(false);
    let refreshFeedback = $state('');
    let reviewColumnElement = $state(null);

    let selected = $derived(selectedId == null ? null : items.find((item) => item.id === selectedId) ?? null);
    let pageSize = $derived(mode === 'history' ? historyPageSize : pendingPageSize);
    let pageCount = $derived(Math.max(1, Math.ceil(total / pageSize)));
    let sortedGroups = $derived([...categoryGroups].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)));
    let sortedCategories = $derived(Object.values(categories).slice().sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)));
    let filteredCategories = $derived(sortedCategories.filter((category) => !reviewCategoryGroupId || category.group === reviewCategoryGroupId));
    let sortedLayers = $derived(Object.values(mapDefinitions).slice().sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)));

    function sessionGuard() {
        const generation = sessionGeneration;
        const user = staffUserId;
        return () => mounted && active && Boolean(user) && staffUserId === user && sessionGeneration === generation;
    }

    function scopeGuard() {
        const sessionCurrent = sessionGuard();
        const game = gameFilter;
        const currentMode = mode;
        const status = historyStatus;
        const currentPage = page;
        const size = pageSize;
        return () => sessionCurrent() && game === gameFilter && currentMode === mode
            && status === historyStatus && currentPage === page && size === pageSize;
    }

    function clearSelection() {
        selectionGeneration += 1;
        revisionGeneration += 1;
        selectedId = null;
        selectionGameUuid = null;
        reviewContext = null;
        categories = {};
        categoryGroups = [];
        mapDefinitions = {};
        contextLoading = false;
        optionsLoading = false;
        optionsError = '';
        historyRevisions = [];
        historyRevisionsLoading = false;
        historyRevisionsLoaded = false;
        revisionsError = '';
        fieldErrors = {};
    }

    function revokeStaffData() {
        sessionGeneration += 1;
        queueGeneration += 1;
        catalogGeneration += 1;
        operationGeneration += 1;
        staffUserId = null;
        gameFilter = 'all';
        page = 1;
        items = [];
        total = 0;
        gameCatalog = [];
        loading = false;
        working = false;
        refreshFeedback = '';
        catalogError = '';
        errorMessage = '';
        successMessage = '';
        clearSelection();
    }

    async function loadGameCatalog() {
        const generation = ++catalogGeneration;
        const sessionCurrent = sessionGuard();
        const isCurrent = () => generation === catalogGeneration && sessionCurrent();
        catalogError = '';
        try {
            const catalog = await loadModerationGameCatalog({ supabase: getSupabaseBrowserClient() });
            if (isCurrent()) gameCatalog = catalog;
        } catch (error) {
            if (!isCurrent()) return;
            gameCatalog = [];
            catalogError = t.loadError;
        }
    }

    async function checkStaffAccess() {
        const generation = ++accessGeneration;
        revokeStaffData();
        const isCurrent = () => mounted && active && generation === accessGeneration;
        try {
            const supabase = getSupabaseBrowserClient();
            const { data, error } = await supabase.auth.getUser();
            if (!isCurrent() || error || !data?.user) return;
            const { data: role, error: roleError } = await supabase.rpc('get_deepmap_role');
            if (!isCurrent()) return;
            if (roleError || !['admin', 'moderator'].includes(role)) {
                errorMessage = t.loadError;
                return;
            }
            staffUserId = data.user.id;
            await Promise.all([loadGameCatalog(), load()]);
        } catch (error) {
            if (isCurrent()) errorMessage = t.loadError;
        }
    }

    onMount(() => {
        mounted = true;
        const supabase = getSupabaseBrowserClient();
        const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
            if (event === 'INITIAL_SESSION') return;
            // A refreshed token for the same staff user does not change review scope.
            if (session?.user?.id === staffUserId && event !== 'SIGNED_OUT') return;
            accessGeneration += 1;
            revokeStaffData();
            // Leave Supabase's synchronous auth callback before asking for role metadata.
            if (session?.user && active) queueMicrotask(() => { if (mounted && active) void checkStaffAccess(); });
        });
        const accountChanged = () => { void checkStaffAccess(); };
        window.addEventListener('deepmap:account-status-changed', accountChanged);
        return () => {
            mounted = false;
            accessGeneration += 1;
            revokeStaffData();
            subscription.unsubscribe();
            window.removeEventListener('deepmap:account-status-changed', accountChanged);
        };
    });

    function localisedLabel(item) {
        return item?.label?.[language] ?? item?.label?.en ?? item?.label?.pt ?? item?.id ?? '';
    }

    function localisedCategory(id) {
        // Historical payloads only carry an adapter, not authoritative historical taxonomy.
        return displayValue(id);
    }

    function formatDate(value) {
        if (!value) return '—';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '—';
        return new Intl.DateTimeFormat(languageKey === 'pt' ? 'pt-PT' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
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

    /** @param {any} item */
    function targetLocation(item) {
        if (!item || reviewContext?.gameUuid !== item.gameUuid || reviewContext?.submissionId !== item.id) return null;
        return reviewContext?.target ?? null;
    }

    /** @param {any} parent */
    function parentLabel(parent) {
        if (!parent) return languageKey === 'pt' ? 'Não resolvido' : 'Unresolved';
        const inactive = languageKey === 'pt' ? 'inativo' : 'inactive';
        return `${localisedLabel(parent)}${parent.isActive === false ? ` (${inactive})` : ''}`;
    }

    /** @typedef {{layers: any[], groups: any[], categories: any[]}} ReviewOptions */

    /** @param {ReviewOptions} options */
    function applyReviewParents(options = { layers: [], groups: [], categories: [] }) {
        const layersByUuid = new Map(options.layers.map((layer) => [layer.uuid, layer]));
        const groupsByUuid = new Map(options.groups.map((group) => [group.uuid, group]));
        const categoriesByUuid = new Map(options.categories.map((category) => [category.uuid, category]));
        if (!reviewContext) return;
        for (const parents of [reviewContext.current, reviewContext.submitted]) {
            // B7e2 metadata wins over option copies, even if the active query disagrees.
            if (parents.layer) layersByUuid.set(parents.layer.uuid, { ...parents.layer, sortOrder: layersByUuid.get(parents.layer.uuid)?.sortOrder ?? 0 });
            if (parents.group) groupsByUuid.set(parents.group.uuid, { ...parents.group, sortOrder: groupsByUuid.get(parents.group.uuid)?.sortOrder ?? 0 });
            if (parents.category) categoriesByUuid.set(parents.category.uuid, { ...parents.category,
                sortOrder: categoriesByUuid.get(parents.category.uuid)?.sortOrder ?? 0,
                group: parents.group?.uuid ?? '', groupId: parents.group?.id ?? null });
        }
        mapDefinitions = Object.fromEntries(layersByUuid);
        categoryGroups = [...groupsByUuid.values()];
        categories = Object.fromEntries(categoriesByUuid);
    }

    /** @param {unknown} value */
    function isOptionText(value) {
        return typeof value === 'string' && value.trim().length > 0;
    }

    /** @param {any} rows @param {'layer' | 'group' | 'category'} kind @param {any} item */
    function normaliseReviewOptions(rows, kind, item) {
        if (!Array.isArray(rows)) throw new Error('REVIEW_OPTIONS_INVALID');
        const uuids = new Set();
        const adapters = new Set();
        return rows.map((/** @type {any} */ row) => {
            const rawUuid = row?.[`${kind}_uuid`];
            const uuid = typeof rawUuid === 'string' ? rawUuid.toLowerCase() : rawUuid;
            if (!row || row.game_uuid !== item.gameUuid || row.game_id !== item.legacyGameId
                || !isCommunityGameUuid(uuid) || !isOptionText(row.id) || row.is_active !== true
                || !Number.isFinite(row.sort_order)
                || (row.name_en !== null && typeof row.name_en !== 'string')
                || (row.name_pt !== null && typeof row.name_pt !== 'string')
                || uuids.has(uuid) || adapters.has(row.id)
                || (kind === 'layer' && !isCommunityGameUuid(row.game_map_id))) throw new Error('REVIEW_OPTIONS_INVALID');
            if (kind === 'category' && !(row.group_id === null && row.group_uuid === null)
                && (!isOptionText(row.group_id) || !isCommunityGameUuid(row.group_uuid))) throw new Error('REVIEW_OPTIONS_GROUP_INVALID');
            uuids.add(uuid);
            adapters.add(row.id);
            return {
                uuid, id: row.id, gameUuid: row.game_uuid, legacyGameId: row.game_id,
                gameMapUuid: kind === 'layer' ? row.game_map_id.toLowerCase() : null,
                label: { en: row.name_en, pt: row.name_pt }, sortOrder: row.sort_order,
                isActive: row.is_active,
                group: kind === 'category' ? row.group_uuid?.toLowerCase() ?? '' : '',
                groupId: kind === 'category' ? row.group_id : null
            };
        });
    }

    /** @param {ReviewOptions} options */
    function validateReviewOptionRelations(options) {
        if (!reviewContext) throw new Error('REVIEW_OPTIONS_CONTEXT_REQUIRED');
        // Detect conflicts before changing collections; labels/active flags stay B7e2-owned.
        for (const kind of /** @type {const} */ (['layer', 'category', 'group'])) {
            const rows = kind === 'layer' ? options.layers : kind === 'category' ? options.categories : options.groups;
            for (const scope of [reviewContext.current, reviewContext.submitted]) {
                const parent = scope[kind];
                if (parent && rows.some((option) => (option.uuid === parent.uuid && option.id !== parent.id)
                    || (option.id === parent.id && option.uuid !== parent.uuid))) throw new Error('REVIEW_OPTIONS_IDENTITY_CONFLICT');
            }
        }
        const knownGroups = [...options.groups, reviewContext.current.group, reviewContext.submitted.group].filter(Boolean);
        for (const category of options.categories) {
            if (category.group && knownGroups.some((group) => (group.uuid === category.group && group.id !== category.groupId)
                || (group.id === category.groupId && group.uuid !== category.group))) throw new Error('REVIEW_OPTIONS_GROUP_INVALID');
        }
    }

    /** @param {any} item @param {() => boolean} isCurrent */
    async function loadReviewOptions(item, isCurrent) {
        optionsLoading = true;
        optionsError = '';
        try {
            if (!isCommunityGameUuid(item.gameUuid) || !isOptionText(item.legacyGameId)) throw new Error('REVIEW_OPTIONS_SCOPE_REQUIRED');
            const supabase = getSupabaseBrowserClient();
            const queries = [
                supabase.from('map_layers').select('id, game_id, game_uuid, layer_uuid, game_map_id, name_en, name_pt, sort_order, is_active'),
                supabase.from('marker_category_groups').select('id, game_id, game_uuid, group_uuid, name_en, name_pt, sort_order, is_active'),
                supabase.from('marker_categories').select('id, game_id, game_uuid, category_uuid, group_id, group_uuid, name_en, name_pt, sort_order, is_active')
            ];
            const results = await Promise.all(queries.map((query) => query.eq('game_uuid', item.gameUuid)
                .eq('game_id', item.legacyGameId).eq('is_active', true).order('sort_order')));
            if (!isCurrent()) return;
            if (results.some((result) => result.error)) throw new Error('REVIEW_OPTIONS_UNAVAILABLE');
            const options = {
                layers: normaliseReviewOptions(results[0].data, 'layer', item),
                groups: normaliseReviewOptions(results[1].data, 'group', item),
                categories: normaliseReviewOptions(results[2].data, 'category', item)
            };
            validateReviewOptionRelations(options);
            applyReviewParents(options);
        } catch (error) {
            if (!isCurrent()) return;
            applyReviewParents();
            optionsError = t.optionsError;
        } finally {
            if (isCurrent()) optionsLoading = false;
        }
    }

    function payloadValue(payload, key, fallback = '') {
        if (payload && Object.prototype.hasOwnProperty.call(payload, key)) return payload[key] ?? '';
        return fallback ?? '';
    }

    function hasPayloadKey(payload, key) {
        return Boolean(payload && Object.prototype.hasOwnProperty.call(payload, key));
    }

    function displayValue(value) {
        if (value == null || String(value).trim() === '') return '—';
        return String(value);
    }

    function contentSummary(items = []) {
        const normalised = reviewItemsFrom(items);
        if (!normalised.length) return '—';
        return normalised
            .map((item) => `${contentTypeLabel(item.type, language)}: ${item[language === 'pt' ? 'textPt' : 'textEn'] || item.textEn || item.textPt || '—'}`)
            .join('\n');
    }

    function valuesDiffer(before, after) {
        return String(before ?? '').trim() !== String(after ?? '').trim();
    }

    function correctionComparisonRows(item) {
        if (!item || item.type !== 'correction') return [];
        const target = targetLocation(item);
        if (!target) return [];
        const payload = item.payload ?? {};
        const rows = [];

        const add = (key, label, before, after, formatter = displayValue) => {
            if (!hasPayloadKey(payload, key) || !valuesDiffer(before, after)) return;
            rows.push({ key, label, before: formatter(before), suggested: formatter(after) });
        };

        const parentChanges = /** @type {Array<[string, 'layer' | 'category', string]>} */ ([['map_layer', 'layer', t.layer], ['category_id', 'category', t.category]]);
        for (const [key, kind, label] of parentChanges) {
            if (!hasPayloadKey(payload, key)) continue;
            const before = reviewContext?.current[kind];
            const after = reviewContext?.submitted[kind];
            if (before?.uuid !== after?.uuid || valuesDiffer(before?.id, payload[key])) {
                rows.push({ key, label, before: parentLabel(before), suggested: parentLabel(after) });
            }
        }
        add('title_en', t.titleEn, target.title?.en, payload.title_en);
        add('title_pt', t.titlePt, target.title?.pt, payload.title_pt);
        add('region_id', t.region, target.regionId, payload.region_id);
        add('description_en', t.descriptionEn, target.description?.en, payload.description_en);
        add('description_pt', t.descriptionPt, target.description?.pt, payload.description_pt);
        add('video_url', t.video, target.videoUrl, payload.video_url);

        if (hasPayloadKey(payload, 'coordinate_x') || hasPayloadKey(payload, 'coordinate_y')) {
            const beforeX = target.coordinates?.[1];
            const beforeY = target.coordinates?.[0];
            const afterX = hasPayloadKey(payload, 'coordinate_x') ? payload.coordinate_x : beforeX;
            const afterY = hasPayloadKey(payload, 'coordinate_y') ? payload.coordinate_y : beforeY;
            if (valuesDiffer(beforeX, afterX) || valuesDiffer(beforeY, afterY)) {
                rows.push({
                    key: 'coordinates',
                    label: t.coordinates,
                    before: `X ${displayValue(beforeX)} · Y ${displayValue(beforeY)}`,
                    suggested: `X ${displayValue(afterX)} · Y ${displayValue(afterY)}`
                });
            }
        }

        if (hasPayloadKey(payload, 'content_items')) {
            const before = contentSummary(target.contentItems ?? []);
            const after = contentSummary(payload.content_items ?? []);
            if (before !== after) rows.push({ key: 'content_items', label: t.content, before, suggested: after });
        }

        if (item.correctionKind === 'image' || hasPayloadKey(payload, 'image_action') || hasPayloadKey(payload, 'image_url') || hasPayloadKey(payload, 'target_image_id')) {
            const imageCount = target.imageCount;
            const before = imageCount === 1
                ? `1 ${language === 'pt' ? 'imagem' : 'image'}`
                : `${imageCount} ${language === 'pt' ? 'imagens' : 'images'}`;
            let suggested = '—';
            if ((payload.image_action ?? 'add') === 'report') {
                suggested = `${t.reportImageSummary}: #${displayValue(payload.target_image_id)}`;
            } else if (payload.image_url) {
                suggested = `${t.addImageSummary}: ${payload.image_url}`;
            }
            rows.push({ key: 'images', label: t.images, before, suggested });
        }

        return rows;
    }

    function populateReviewForm(item) {
        const payload = item?.payload ?? {};
        const target = targetLocation(item);
        const layer = hasPayloadKey(payload, 'map_layer') ? reviewContext?.submitted.layer : reviewContext?.current.layer;
        const category = hasPayloadKey(payload, 'category_id') ? reviewContext?.submitted.category : reviewContext?.current.category;
        const group = hasPayloadKey(payload, 'category_id') ? reviewContext?.submitted.group : reviewContext?.current.group;
        reviewLayerKey = layer?.uuid ?? '';
        reviewCategoryKey = category?.uuid ?? '';
        reviewMapLayer = layer?.id ?? '';
        reviewCategoryId = category?.id ?? '';
        reviewCategoryGroupId = group?.uuid ?? '';
        reviewTitleEn = String(payloadValue(payload, 'title_en', target?.title?.en ?? ''));
        reviewTitlePt = String(payloadValue(payload, 'title_pt', target?.title?.pt ?? ''));
        reviewRegionId = String(payloadValue(payload, 'region_id', target?.regionId ?? ''));
        reviewDescriptionEn = String(payloadValue(payload, 'description_en', target?.description?.en ?? ''));
        reviewDescriptionPt = String(payloadValue(payload, 'description_pt', target?.description?.pt ?? ''));
        reviewVideoUrl = String(payloadValue(payload, 'video_url', target?.videoUrl ?? ''));
        reviewCoordinateX = String(payloadValue(payload, 'coordinate_x', target?.coordinates?.[1] ?? ''));
        reviewCoordinateY = String(payloadValue(payload, 'coordinate_y', target?.coordinates?.[0] ?? ''));
        reviewContentItems = reviewItemsFrom(hasPayloadKey(payload, 'content_items') ? payload.content_items : target?.contentItems ?? []);
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
        if (!reviewMapLayer || !mapDefinitions[reviewLayerKey] || mapDefinitions[reviewLayerKey].id !== reviewMapLayer) errors.layer = t.required;
        if (!reviewCategoryId || !categories[reviewCategoryKey] || categories[reviewCategoryKey].id !== reviewCategoryId) errors.category = t.required;
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
            title_pt: reviewTitlePt.trim() || null,
            region_id: reviewRegionId.trim(),
            description_en: reviewDescriptionEn.trim(),
            description_pt: reviewDescriptionPt.trim() || null,
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
        if (!item || !reviewContext || reviewContext.gameUuid !== item.gameUuid
            || reviewContext.submissionId !== item.id) return null;
        const game = gameCatalog.find((game) => game.gameUuid === item.gameUuid);
        const base = `/games/${encodeURIComponent(reviewContext.gameSlug)}/map`;
        const renderer = getGameRendererBySlug(reviewContext.gameSlug);
        if (!game?.publicGameMapUuid || renderer?.mapHref !== base) return null;
        const finalLayer = mapDefinitions[reviewLayerKey];
        const finalCategory = categories[reviewCategoryKey];
        if (!finalLayer || finalLayer.gameMapUuid !== game.publicGameMapUuid || !finalCategory) return null;
        // Preserve the pre-B7f2 payload-first preview; form values only fill absent/null keys.
        const payload = item.payload ?? {};
        const layer = payload.map_layer != null ? reviewContext.submitted.layer : finalLayer;
        if (!layer || layer.isActive !== true || layer.gameMapUuid !== game.publicGameMapUuid
            || (reviewContext.current.layer && reviewContext.current.layer.gameMapUuid !== game.publicGameMapUuid)
            || (payload.category_id != null && !reviewContext.submitted.category)) return null;
        const xRaw = payload.coordinate_x ?? reviewCoordinateX;
        const yRaw = payload.coordinate_y ?? reviewCoordinateY;
        const x = hasCoordinateValue(xRaw) ? Number(xRaw) : NaN;
        const y = hasCoordinateValue(yRaw) ? Number(yRaw) : NaN;
        const hasSubmittedCoordinates = Number.isFinite(x) && Number.isFinite(y)
            && (payload.coordinate_x != null || payload.coordinate_y != null || item.type === 'create');

        if (!hasSubmittedCoordinates && item.markerId && reviewContext.target?.isPublished) {
            return `${base}?marker=${encodeURIComponent(item.markerId)}`;
        }

        const category = payload.category_id != null ? reviewContext.submitted.category : finalCategory;
        const params = new URLSearchParams();
        if (Number.isFinite(x) && Number.isFinite(y)) {
            params.set('reviewX', String(x));
            params.set('reviewY', String(y));
            params.set('layer', layer.id);
            if (category) params.set('category', category.id);
        }
        if (item.markerId) params.set('marker', String(item.markerId));
        params.set('submission', String(item.id));
        return `${base}?${params.toString()}`;
    }

    async function load({ preserveSelection = false } = {}) {
        const generation = ++queueGeneration;
        if (!mounted || !active || !staffUserId) return;
        const scopeCurrent = scopeGuard();
        const isCurrent = () => generation === queueGeneration && scopeCurrent();
        const gameUuid = gameFilter === 'all' ? null : gameFilter;
        const status = mode === 'pending' ? 'pending' : historyStatus;
        const requestedPage = page;
        const size = pageSize;
        if (!preserveSelection) clearSelection();
        loading = true;
        errorMessage = '';
        successMessage = '';
        try {
            let result = await loadMarkerSubmissionsPage({
                supabase: getSupabaseBrowserClient(),
                gameUuid, status, limit: size, offset: (requestedPage - 1) * size
            });
            if (!isCurrent()) return;
            if (!result.items.length && requestedPage > 1) {
                result = await loadMarkerSubmissionsPage({ supabase: getSupabaseBrowserClient(), gameUuid, status, limit: size, offset: 0 });
                if (!isCurrent()) return;
                page = Math.min(requestedPage, Math.max(1, Math.ceil(result.total / size)));
                return await load();
            }
            if (result.items.some((item) => !isCommunityGameUuid(item.gameUuid)
                || item.status !== status || (gameUuid !== null && item.gameUuid !== gameUuid))) throw new Error('MODERATION_SCOPE_MISMATCH');
            items = result.items;
            total = result.total;
            if (selectedId !== null && !items.some((item) => item.id === selectedId && item.gameUuid === selectionGameUuid)) clearSelection();
        } catch (error) {
            if (!isCurrent()) return;
            console.error('DeepMap global moderation:', error);
            items = [];
            total = 0;
            clearSelection();
            errorMessage = t.loadError;
        } finally {
            if (isCurrent()) loading = false;
        }
    }

    async function loadHistoryRevisions(submissionId) {
        const generation = ++revisionGeneration;
        const scopeCurrent = scopeGuard();
        const selectedGame = selected?.gameUuid;
        const isCurrent = () => generation === revisionGeneration && scopeCurrent()
            && selectedId === submissionId && selected?.gameUuid === selectedGame;
        historyRevisions = [];
        revisionsError = '';
        historyRevisionsLoaded = false;
        if (mode !== 'history' || submissionId == null) return;
        historyRevisionsLoading = true;
        try {
            const { data, error } = await getSupabaseBrowserClient().rpc('get_marker_submission_revisions', {
                p_submission_id: markerIdKey(submissionId)
            });
            if (!isCurrent()) return;
            if (error) throw error;
            historyRevisions = (data ?? []).map((row) => ({
                revisionNo: Number(row.revision_no ?? 0),
                editedUsername: row.edited_username ?? null,
                payload: row.payload ?? {},
                note: row.note ?? '',
                createdAt: row.created_at
            }));
        } catch (error) {
            if (!isCurrent()) return;
            console.warn('DeepMap moderation revisions:', error?.message ?? error);
            historyRevisions = [];
            revisionsError = t.loadError;
        } finally {
            if (isCurrent()) {
                historyRevisionsLoading = false;
                historyRevisionsLoaded = true;
            }
        }
    }


    async function handlePageSizeChange() {
        page = 1;
        selectedId = null;
        historyRevisions = [];
        historyRevisionsLoaded = false;
        await tick();
        await load();
    }

    async function refreshQueue() {
        if (loading || working) return;
        const scopeCurrent = scopeGuard();
        refreshFeedback = '';
        const catalogRequest = loadGameCatalog();
        const queueRequest = load();
        const generation = queueGeneration;
        await Promise.all([catalogRequest, queueRequest]);
        if (generation === queueGeneration && scopeCurrent() && !errorMessage) {
            refreshFeedback = t.refreshed;
            window.setTimeout(() => {
                if (generation === queueGeneration && scopeCurrent()) refreshFeedback = '';
            }, 2200);
        }
    }

    async function selectSubmission(item) {
        if (!mounted || !active || !staffUserId || loading || !items.some((row) => row.id === item.id && row.gameUuid === item.gameUuid)) return;
        if (selectedId === item.id) {
            clearSelection();
            return;
        }
        clearSelection();
        const generation = selectionGeneration;
        const scopeCurrent = scopeGuard();
        const isCurrent = () => generation === selectionGeneration && scopeCurrent() && selectedId === item.id;
        selectedId = item.id;
        selectionGameUuid = item.gameUuid;
        contextLoading = true;
        errorMessage = '';
        successMessage = '';
        try {
            const context = await loadMarkerReviewContext({ supabase: getSupabaseBrowserClient(), gameUuid: item.gameUuid, submissionId: item.id });
            if (!isCurrent()) return;
            reviewContext = context;
            items = items.map((row) => row.id !== item.id ? row : { ...row,
                payload: context.payload, status: context.status, gameSlug: context.gameSlug,
                gameName: context.gameName, legacyGameId: context.legacyGameId });
            applyReviewParents();
            const contextItem = { ...item, payload: context.payload, status: context.status, legacyGameId: context.legacyGameId };
            populateReviewForm(contextItem);
            contextLoading = false;
            const optionsRequest = loadReviewOptions(contextItem, isCurrent);
            if (mode === 'history') await Promise.all([optionsRequest, loadHistoryRevisions(item.id)]);
            else await optionsRequest;
            if (!isCurrent()) return;
            if (typeof window !== 'undefined' && window.matchMedia('(max-width: 900px)').matches) {
                window.setTimeout(() => { if (isCurrent()) reviewColumnElement?.scrollIntoView({ behavior: 'smooth', block: 'start' }); }, 0);
            }
        } catch (error) {
            if (!isCurrent()) return;
            reviewContext = null;
            console.error('DeepMap moderation game context:', error);
            errorMessage = t.reviewError;
        } finally {
            if (isCurrent()) contextLoading = false;
        }
    }

    async function review(decision) {
        if (!selected || selected.status !== 'pending' || working || contextLoading
            || (decision === 'approved' && optionsLoading)
            || reviewContext?.submissionId !== selected.id || reviewContext?.gameUuid !== selected.gameUuid
            || !['approved', 'rejected'].includes(decision)) return;
        const item = selected;
        const generation = ++operationGeneration;
        const selectedGeneration = selectionGeneration;
        const scopeCurrent = scopeGuard();
        const sessionCurrent = sessionGuard();
        const isCurrent = () => generation === operationGeneration && scopeCurrent()
            && selectedGeneration === selectionGeneration && selectedId === item.id;
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
                submissionId: item.id,
                decision,
                reviewNote,
                payloadOverride: decision === 'approved' ? buildReviewPayload() : null
            });
            if (!isCurrent()) {
                if (sessionCurrent()) {
                    if (selectedId === item.id) clearSelection();
                    await load({ preserveSelection: true });
                }
                return;
            }
            clearSelection();
            const refreshCurrent = scopeGuard();
            const refreshGeneration = queueGeneration + 1;
            await load();
            if (refreshCurrent() && refreshGeneration === queueGeneration && generation === operationGeneration
                && selectedId === null && !errorMessage) successMessage = decision === 'approved' ? t.approvedOk : t.rejectedOk;
        } catch (error) {
            if (!isCurrent()) return;
            console.error('DeepMap global moderation review:', error);
            errorMessage = t.reviewError;
        } finally {
            if (generation === operationGeneration && sessionCurrent()) working = false;
        }
    }

    async function setMode(nextMode) {
        if (mode === nextMode) return;
        mode = nextMode;
        page = 1;
        selectedId = null;
        historyRevisions = [];
        await load();
    }

    async function setHistoryStatus(status) {
        if (historyStatus === status && mode === 'history') return;
        historyStatus = status;
        mode = 'history';
        page = 1;
        selectedId = null;
        historyRevisions = [];
        await load();
    }

    async function setGameFilter(event) {
        gameFilter = event.currentTarget.value;
        page = 1;
        selectedId = null;
        historyRevisions = [];
        await load();
    }

    async function goPage(nextPage) {
        if (nextPage < 1 || nextPage > pageCount || nextPage === page) return;
        page = nextPage;
        selectedId = null;
        historyRevisions = [];
        await load();
    }

    function handleCategoryGroupChange() {
        if (reviewCategoryKey && categories[reviewCategoryKey]?.group !== reviewCategoryGroupId) {
            reviewCategoryKey = '';
            reviewCategoryId = '';
        }
        fieldErrors = { ...fieldErrors, category: undefined };
    }

    function handleReviewLayerChange() {
        reviewMapLayer = mapDefinitions[reviewLayerKey]?.id ?? '';
    }

    function handleReviewCategoryChange() {
        reviewCategoryId = categories[reviewCategoryKey]?.id ?? '';
    }

    $effect(() => {
        const enabled = active;
        untrack(() => {
            if (enabled) void checkStaffAccess();
            else { accessGeneration += 1; revokeStaffData(); }
        });
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
            <label class="map-filter"><span>{t.map}</span><select value={gameFilter} onchange={setGameFilter}><option value="all">{t.allMaps}</option>{#each gameCatalog as game}<option value={game.gameUuid}>{game.gameName} · {game.gameSlug}</option>{/each}</select></label>
            <label class="page-size"><span>{t.perPage}</span>{#if mode === 'history'}<select bind:value={historyPageSize} onchange={handlePageSizeChange} disabled={loading || working}><option value={10}>10</option><option value={20}>20</option><option value={50}>50</option></select>{:else}<select bind:value={pendingPageSize} onchange={handlePageSizeChange} disabled={loading || working}><option value={10}>10</option><option value={20}>20</option><option value={50}>50</option></select>{/if}</label><div class="refresh-control"><button type="button" onclick={refreshQueue} disabled={loading || working}>{loading ? t.refreshing : t.refresh}</button>{#if refreshFeedback}<small class="refresh-feedback" role="status">{refreshFeedback}</small>{/if}</div>
        </div>
    </div>

    <div class="mode-tabs" role="tablist">
        <button class:active={mode === 'pending'} type="button" onclick={() => setMode('pending')}>{t.pending}</button>
        <button class:active={mode === 'history' && historyStatus === 'approved'} type="button" onclick={() => setHistoryStatus('approved')}>{t.approved}</button>
        <button class:active={mode === 'history' && historyStatus === 'rejected'} type="button" onclick={() => setHistoryStatus('rejected')}>{t.rejected}</button>
    </div>

    {#if errorMessage}<p class="message error" role="alert">{errorMessage}</p>{/if}
    {#if catalogError}<p class="message error" role="alert">{catalogError}</p>{/if}
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
                            <span class="queue-top"><b>{item.gameName ?? item.gameSlug ?? item.gameUuid}</b><em>#{item.id}</em></span>
                            <strong>{item.type === 'create' ? t.newMarker : t.correction}</strong>
                            <small>@{item.submittedUsername ?? '—'} · {item.revisionCount} {t.versions}{#if item.status !== 'pending'} · {formatDate(item.reviewedAt)} · {t.viewDetails}{/if}</small>
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

        <div class="review-column" bind:this={reviewColumnElement}>
            {#if selected}
                <article class="review-card">
                    <div class="review-head">
                        <div>
                            <span class="eyebrow">{selected.gameName ?? selected.gameSlug ?? selected.gameUuid}</span>
                            <h3>#{selected.id} · {selected.type === 'create' ? t.newMarker : t.correction}</h3>
                        </div>
                        <div class="review-head-actions">{#if mapHref(selected)}<a href={mapHref(selected)} target="_blank" rel="noreferrer">{t.openMap}</a>{/if}<button type="button" onclick={clearSelection}>{t.close}</button></div>
                    </div>

                    {#if contextLoading}
                        <p>…</p>
                    {:else if !reviewContext}
                        <p class="message error">{t.reviewError}</p>
                    {:else}
                    {#if optionsError}<p class="message error" role="alert">{optionsError}</p>{/if}
                    <div class="meta-grid">
                        <span>{t.submittedBy}<strong>@{selected.submittedUsername ?? '—'}</strong></span>
                        <span>{t.marker}<strong>{selected.markerId ? `#${selected.markerId}` : t.newMarker}</strong></span>
                        {#if selected.status !== 'pending'}
                            <span>{t.reviewedBy}<strong>@{selected.reviewedUsername ?? '—'}</strong></span>
                            <span>{t.reviewedAt}<strong>{formatDate(selected.reviewedAt)}</strong></span>
                        {/if}
                    </div>

                    <div class="meta-grid">
                        <span>{t.current} · {t.layer}<strong>{parentLabel(reviewContext.current.layer)}</strong></span>
                        <span>{t.current} · {t.category}<strong>{parentLabel(reviewContext.current.category)}</strong></span>
                        <span>{t.current} · {t.type}<strong>{parentLabel(reviewContext.current.group)}</strong></span>
                        <span>{t.suggested} · {t.layer}<strong>{parentLabel(reviewContext.submitted.layer)}</strong></span>
                        <span>{t.suggested} · {t.category}<strong>{parentLabel(reviewContext.submitted.category)}</strong></span>
                        <span>{t.suggested} · {t.type}<strong>{parentLabel(reviewContext.submitted.group)}</strong></span>
                        {#if reviewContext.target}
                            <span>{t.current} · {t.marker}<strong>{reviewContext.target.isPublished ? (languageKey === 'pt' ? 'Publicado' : 'Published') : (languageKey === 'pt' ? 'Não publicado' : 'Unpublished')}</strong></span>
                            <span>{t.current} · {t.images}<strong>{reviewContext.target.imageCount}</strong></span>
                        {/if}
                    </div>

                    {#if selected.status === 'pending'}
                        {#if selected.type === 'correction'}
                            <section class="comparison-panel" aria-label={t.comparison}>
                                <div class="comparison-heading"><strong>{t.comparison}</strong><small>{t.comparisonHelp}</small></div>
                                {#if targetLocation(selected)}
                                    {@const comparisonRows = correctionComparisonRows(selected)}
                                    {#if comparisonRows.length}
                                        <div class="comparison-table">
                                            <div class="comparison-header"><span></span><b>{t.current}</b><b>{t.suggested}</b></div>
                                            {#each comparisonRows as row (row.key)}
                                                <div class="comparison-row">
                                                    <strong>{row.label}</strong>
                                                    <div class="comparison-value current-value"><small class="value-label">{t.current}</small>{row.before}</div>
                                                    <div class="comparison-value suggested-value"><small class="value-label">{t.suggested}</small>{row.suggested}</div>
                                                </div>
                                            {/each}
                                        </div>
                                    {:else}
                                        <p class="comparison-empty">{t.noStructuredChanges}</p>
                                    {/if}
                                {:else}
                                    <p class="comparison-empty">{t.noCurrentMarker}</p>
                                {/if}
                            </section>
                        {/if}
                        <div class="review-intro"><strong>{selected.type === 'correction' ? t.finalVersion : t.review}</strong><small>{t.reviewHelp}</small></div>
                        <div class="form-grid two">
                            <label class:invalid={Boolean(fieldErrors.layer)}><span>{t.layer} *</span><select bind:value={reviewLayerKey} onchange={handleReviewLayerChange} disabled={working || optionsLoading}><option value="">{parentLabel(null)}</option>{#each sortedLayers as layer}<option value={layer.uuid}>{parentLabel(layer)}</option>{/each}</select>{#if fieldErrors.layer}<small class="field-error">{fieldErrors.layer}</small>{/if}</label>
                            <label><span>{t.type}</span><select bind:value={reviewCategoryGroupId} onchange={handleCategoryGroupChange} disabled={working || optionsLoading}><option value="">—</option>{#each sortedGroups as group}<option value={group.uuid}>{parentLabel(group)}</option>{/each}</select></label>
                        </div>
                        <label class:invalid={Boolean(fieldErrors.category)}><span>{t.category} *</span><select bind:value={reviewCategoryKey} onchange={handleReviewCategoryChange} disabled={working || optionsLoading}><option value="">{t.chooseCategory}</option>{#each filteredCategories as category}<option value={category.uuid}>{parentLabel(category)}</option>{/each}</select>{#if fieldErrors.category}<small class="field-error">{fieldErrors.category}</small>{/if}</label>
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
                        <div class="actions"><button class="approve" type="button" onclick={() => review('approved')} disabled={working || optionsLoading}>{working ? t.working : t.approve}</button><button class="reject" type="button" onclick={() => review('rejected')} disabled={working}>{t.reject}</button><button type="button" onclick={clearSelection} disabled={working}>{t.close}</button></div>
                    {:else}
                        <section class="history-result" aria-label={t.historyDetails}>
                            <strong>{t.historyDetails}</strong>
                            <div>
                                <span>{t.decision}<b>{selected.status === 'approved' ? t.approved : t.rejected}</b></span>
                                <span>{t.submittedAt}<b>{formatDate(selected.createdAt)}</b></span>
                                <span>{t.reviewedBy}<b>@{selected.reviewedUsername ?? '—'}</b></span>
                                <span>{t.reviewedAt}<b>{formatDate(selected.reviewedAt)}</b></span>
                            </div>
                        </section>

                        {#if selected.type === 'correction' && selected.status === 'rejected' && targetLocation(selected)}
                            {@const historicalComparisonRows = correctionComparisonRows(selected)}
                            {#if historicalComparisonRows.length}
                                <section class="comparison-panel" aria-label={t.comparison}>
                                    <div class="comparison-heading"><strong>{t.comparison}</strong><small>{t.comparisonHelp}</small></div>
                                    <div class="comparison-table">
                                        <div class="comparison-header"><span></span><b>{t.current}</b><b>{t.suggested}</b></div>
                                        {#each historicalComparisonRows as row (row.key)}
                                            <div class="comparison-row">
                                                <strong>{row.label}</strong>
                                                <div class="comparison-value current-value"><small class="value-label">{t.current}</small>{row.before}</div>
                                                <div class="comparison-value suggested-value"><small class="value-label">{t.suggested}</small>{row.suggested}</div>
                                            </div>
                                        {/each}
                                    </div>
                                </section>
                            {/if}
                        {/if}

                        {#if revisionsError}<p class="message error" role="alert">{revisionsError}</p>{/if}
                        {#if historyRevisionsLoading}
                            <div class="revision-history"><strong>{t.revisionsHistory}</strong><p>…</p></div>
                        {:else if historyRevisions.length}
                            <section class="revision-history" aria-label={t.revisionsHistory}>
                                <strong>{t.revisionsHistory}</strong>
                                <div class="revision-list">
                                    {#each historyRevisions as revision (revision.revisionNo)}
                                        <article>
                                            <header><b>{t.revision} {revision.revisionNo}</b><span>{revision.editedUsername ? `@${revision.editedUsername}` : '—'} · {formatDate(revision.createdAt)}</span></header>
                                            {#if revision.payload?.title_en}<p>EN: {revision.payload.title_en}</p>{/if}
                                            {#if revision.payload?.title_pt}<p>PT: {revision.payload.title_pt}</p>{/if}
                                            {#if revision.payload?.category_id}<p>{t.category}: {localisedCategory(revision.payload.category_id)}</p>{/if}
                                            {#if revision.payload?.coordinate_x != null && revision.payload?.coordinate_y != null}<p>{t.coordinates}: X {revision.payload.coordinate_x} · Y {revision.payload.coordinate_y}</p>{/if}
                                            {#if revision.note}<p><span>{t.note}:</span> {revision.note}</p>{/if}
                                        </article>
                                    {/each}
                                </div>
                            </section>
                        {:else if historyRevisionsLoaded && selected.revisionCount === 0}
                            <section class="revision-history legacy-history" aria-label={t.revisionsHistory}><strong>{t.revisionsHistory}</strong><p>{t.legacyDetails}</p></section>
                        {/if}

                        <div class="proposal">
                            <strong>{t.changes}</strong>
                            {#if hasPayloadKey(selected.payload, 'map_layer')}<p>{t.layer}: {parentLabel(reviewContext.submitted.layer)} · {displayValue(selected.payload.map_layer)}</p>{/if}
                            {#if hasPayloadKey(selected.payload, 'category_id')}<p>{t.category}: {parentLabel(reviewContext.submitted.category)} · {displayValue(selected.payload.category_id)}</p>{/if}
                            {#if selected.payload?.title_en}<p>EN: {selected.payload.title_en}</p>{/if}
                            {#if selected.payload?.title_pt}<p>PT: {selected.payload.title_pt}</p>{/if}
                            {#if selected.payload?.region_id}<p>{t.region}: {selected.payload.region_id}</p>{/if}
                            {#if selected.payload?.description_en}<p>{t.descriptionEn}: {selected.payload.description_en}</p>{/if}
                            {#if selected.payload?.description_pt}<p>{t.descriptionPt}: {selected.payload.description_pt}</p>{/if}
                            {#if selected.payload?.video_url}<p>{t.video}: {selected.payload.video_url}</p>{/if}
                            {#if selected.payload?.coordinate_x != null && selected.payload?.coordinate_y != null}<p>{t.coordinates}: X {selected.payload.coordinate_x} · Y {selected.payload.coordinate_y}</p>{/if}
                            {#if selected.payload?.image_url}<p>{t.imageUrl}: {selected.payload.image_url}</p>{/if}
                            {#if selected.payload?.content_items?.length}<div><b>{t.content}</b>{#each selected.payload.content_items as contentItem}<p><span>{contentTypeLabel(contentItem.type, language)}:</span> {contentItem[`text_${language}`] || contentItem.text_en || contentItem.text_pt || '—'}</p>{/each}</div>{/if}
                        </div>
                        {#if selected.note}<p class="note"><b>{t.note}:</b> {selected.note}</p>{/if}
                        {#if selected.reviewNote}<p class="note"><b>{t.moderatorNote}:</b> {selected.reviewNote}</p>{/if}
                    {/if}
                    {/if}
                </article>
            {:else}
                <div class="review-placeholder"><strong>{mode === 'pending' ? t.pending : t.history}</strong><p>{languageKey === 'pt' ? 'Seleciona uma submissão para a rever.' : 'Select a submission to review it.'}</p></div>
            {/if}
        </div>
    </div>
</section>
{/if}

<style>
    .global-moderation{display:grid;gap:16px;color:#eee}.toolbar{display:flex;align-items:flex-end;justify-content:space-between;gap:14px}.toolbar h2{margin:2px 0 0;font-size:1.35rem}.eyebrow{color:#c8a355;font-size:.68rem;font-weight:900;text-transform:uppercase;letter-spacing:.08em}.toolbar-actions{display:flex;align-items:flex-end;gap:8px;flex-wrap:wrap}.toolbar button,.toolbar select,.mode-tabs button,.pagination button,.review-head-actions button,.review-head-actions a,.actions button{border:1px solid #3b3b45;border-radius:8px;background:#17171c;color:#ddd;cursor:pointer;text-decoration:none}.toolbar button{padding:9px 12px}.refresh-control{display:grid;justify-items:end;gap:4px}.refresh-feedback{color:#8fd3a3;font-size:.64rem;font-weight:800;white-space:nowrap}.legacy-history{border-style:dashed}.map-filter,.page-size{display:grid;min-width:110px;gap:4px}.map-filter span,.page-size span{white-space:nowrap;font-size:.68rem;color:#999}.map-filter select{min-width:170px;padding:8px;background:#111116;color:#eee}.page-size select{width:100%;min-width:92px;padding:8px;background:#111116;color:#eee}.mode-tabs{display:flex;gap:7px;flex-wrap:wrap}.mode-tabs button{padding:8px 12px;font-weight:800}.mode-tabs button.active,.pagination button.active{border-color:#c8a355;background:#211d14;color:#f0d28a}.moderation-layout{display:grid;grid-template-columns:minmax(260px,360px) minmax(0,1fr);gap:14px;align-items:start}.queue-column,.review-column{min-width:0}.queue{display:grid;gap:7px}.queue>button{display:grid;gap:4px;padding:10px;border:1px solid #303039;border-radius:9px;background:#111115;color:#ddd;text-align:left;cursor:pointer}.queue>button:hover,.queue>button.selected{border-color:#c8a355;background:#1d1a13}.queue-top{display:flex;align-items:center;justify-content:space-between;gap:8px}.queue-top b{color:#d8b86f;font-size:.72rem}.queue-top em{color:#73737d;font-size:.66rem;font-style:normal}.queue small{color:#9696a0}.pagination{display:flex;gap:5px;justify-content:center;flex-wrap:wrap;margin-top:10px}.pagination button{min-width:32px;height:32px}.review-card,.review-placeholder,.empty{border:1px solid #303039;border-radius:12px;background:#101014}.review-card{display:grid;gap:12px;padding:14px}.review-placeholder,.empty{min-height:150px;display:grid;place-items:center;align-content:center;gap:6px;padding:18px;color:#92929c;text-align:center}.review-placeholder strong,.empty strong{color:#e4e4e7}.review-placeholder p{margin:0}.review-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}.review-head h3{margin:3px 0 0}.review-head-actions{display:flex;gap:6px;flex-wrap:wrap}.review-head-actions a,.review-head-actions button{padding:7px 9px;font-size:.72rem}.review-head-actions a{border-color:#66593b;color:#d8b86f}.meta-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}.meta-grid span{display:grid;color:#8f8f98;font-size:.68rem}.meta-grid strong{color:#eee;font-size:.78rem}.comparison-panel{display:grid;gap:9px;padding:11px;border:1px solid #303039;border-radius:10px;background:#0b0b0f}.comparison-heading{display:grid;gap:3px}.comparison-heading strong{color:#d8b86f}.comparison-heading small{color:#8f8f98}.comparison-table{display:grid;gap:6px}.comparison-header,.comparison-row{display:grid;grid-template-columns:minmax(110px,.55fr) minmax(0,1fr) minmax(0,1fr);gap:7px;align-items:stretch}.comparison-header{padding:0 3px;color:#8f8f98;font-size:.68rem}.comparison-header b:last-child{color:#d8b86f}.comparison-row>strong{align-self:start;padding:9px 8px;color:#aaa;font-size:.7rem}.comparison-value{padding:9px;border:1px solid #2f2f38;border-radius:8px;white-space:pre-wrap;overflow-wrap:anywhere;font-size:.76rem;line-height:1.4}.value-label{display:none;margin-bottom:3px;color:#777;font-size:.6rem;font-weight:900;text-transform:uppercase;letter-spacing:.04em}.current-value{background:#111116;color:#aaa}.suggested-value{border-color:#5f5338;background:#1b1811;color:#eee}.comparison-empty{margin:0;color:#9a9aa4;font-size:.76rem}.review-intro{display:grid;gap:3px;padding-top:9px;border-top:1px solid #2b2b33}.review-intro strong{color:#d8b86f}.review-intro small{color:#8f8f98}.form-grid{display:grid;gap:9px}.form-grid.two{grid-template-columns:1fr 1fr}label{display:grid;gap:5px}label span,legend{color:#aaa;font-size:.7rem;font-weight:700}input,select,textarea{width:100%;min-width:0;box-sizing:border-box;padding:8px;border:1px solid #34343e;border-radius:8px;background:#0d0d11;color:#eee;font:inherit}textarea{resize:vertical}label.invalid input,label.invalid select,label.invalid textarea{border-color:#c85f67}.field-error{color:#ff9da7;font-size:.66rem}.location-box{margin:0;padding:10px;border:1px solid #303039;border-radius:9px}.coordinate-row{display:grid;grid-template-columns:36px minmax(0,1fr);gap:7px;align-items:center;margin:7px 0}.coordinate-row>.field-error{grid-column:2}.actions{display:flex;gap:8px;flex-wrap:wrap;padding-top:9px;border-top:1px solid #2d2d35;background:#101014}.actions button{padding:9px 12px}.actions .approve{border-color:#c8a355;background:#c8a355;color:#111;font-weight:900}.actions .reject{border-color:#704047;color:#ffc0c8}.note{margin:0;color:#c7c7ce;font-size:.78rem}.revision-history{display:grid;gap:8px;padding:10px;border:1px solid #303039;border-radius:9px;background:#0c0c10}.revision-history>strong{color:#d8b86f}.revision-history>p{margin:0;color:#8f8f98}.revision-list{display:grid;gap:7px}.revision-list article{padding:8px;border:1px solid #292931;border-radius:8px;background:#111116}.revision-list header{display:flex;justify-content:space-between;gap:10px;margin-bottom:5px}.revision-list header b{color:#e4c982;font-size:.72rem}.revision-list header span{color:#777;font-size:.64rem}.revision-list p{margin:4px 0;color:#b9b9c1;font-size:.72rem;overflow-wrap:anywhere}.revision-list p span{color:#d8b86f;font-weight:800}.history-result{display:grid;gap:8px;padding:10px;border:1px solid #3b3526;border-radius:9px;background:#15130e}.history-result>strong{color:#d8b86f}.history-result>div{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}.history-result span{display:grid;gap:2px;color:#8f8f98;font-size:.66rem}.history-result b{color:#e7e7eb;font-size:.75rem}.proposal{padding:10px;border:1px solid #2f2f38;border-radius:9px;background:#0b0b0e}.proposal>strong{color:#c8a355}.proposal p{margin:5px 0;color:#c1c1c8;font-size:.78rem}.proposal p span{color:#d8b86f;font-weight:800}.message{margin:0;padding:9px;border-radius:8px}.message.error{background:#2b1519;color:#ffc0c8}.message.success{background:#15251a;color:#bcebc7}
    @media(max-width:900px){.history-result>div{grid-template-columns:1fr 1fr}.moderation-layout{grid-template-columns:1fr}.queue-column{max-height:38vh;overflow:auto;touch-action:pan-y}.review-column{min-height:0}.meta-grid{grid-template-columns:1fr 1fr}}
    @media(max-width:600px){.history-result>div{grid-template-columns:1fr}.comparison-header{display:none}.comparison-row{grid-template-columns:1fr;gap:5px;padding:8px 0;border-bottom:1px solid #25252d}.comparison-row:last-child{border-bottom:0}.comparison-row>strong{padding:0 2px;color:#d6d6dc}.comparison-value{padding:7px 8px;font-size:.7rem}.value-label{display:block}.toolbar{align-items:stretch;flex-direction:column}.toolbar-actions,.map-filter,.map-filter select{width:100%}.page-size{min-width:110px}.refresh-control{width:100%;justify-items:stretch}.refresh-feedback{text-align:center}.toolbar button{flex:1}.mode-tabs{display:grid;grid-template-columns:repeat(3,1fr)}.mode-tabs button{padding:8px 5px}.review-card{padding:10px}.review-head{flex-direction:column}.review-head-actions{width:100%}.review-head-actions a,.review-head-actions button{flex:1;text-align:center}.meta-grid,.form-grid.two{grid-template-columns:1fr}.actions{margin:4px 0 0;padding:10px 0 0}.actions button{flex:1}.queue-column{max-height:32vh}}
</style>
