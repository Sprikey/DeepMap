<script>
    import { tick } from 'svelte';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import { normaliseHttpUrl } from '$lib/map/media.js';
    import CoordinateStepper from '$lib/editor/CoordinateStepper.svelte';
    import MarkerContentEditor from '$lib/editor/MarkerContentEditor.svelte';
    import { serialiseMarkerContentItems } from '$lib/editor/marker-content.js';
    import {
        cancelMarkerSubmission,
        createMarkerSubmission,
        ensureContributorProfile,
        findPendingMarkerCorrection,
        loadMyMarkerSubmissionsPage,
        normaliseSubmission,
        updateMarkerSubmission
    } from '$lib/community/marker-contributions.js';

    let {
        gameId,
        language = 'en',
        active = false,
        userId = null,
        userRole = 'user',
        requestMode = 'create',
        requestMarker = null,
        requestRevision = 0,
        focusSubmissionId = null,
        point = null,
        categories = {},
        categoryGroups = [],
        mapDefinitions = {},
        positionModeActive = false,
        mobilePositionFlow = false,
        onClose = () => {},
        onPreview = () => {},
        onPositionModeChange = () => {},
        onSubmitted = async () => {}
    } = $props();

    const TEXT = {
        en: {
            title: 'Community contribution', addMarker: 'Add marker', myContributions: 'My contributions',
            suggestCorrection: 'Suggest a correction', pending: 'Pending', approved: 'Approved', rejected: 'Rejected', cancelled: 'Cancelled',
            editPending: 'Edit pending submission', close: 'Close', refresh: 'Refresh', refreshing: 'Refreshing…', refreshed: 'Updated just now ✓', perPage: 'Per page', page: 'Page', newContribution: 'New contribution',
            layer: 'Map layer', type: 'Type', category: 'Category', chooseCategory: 'Choose a category…', titleEn: 'Title — EN', titlePt: 'Title — PT',
            region: 'Region', descriptionEn: 'Description — EN', descriptionPt: 'Description — PT', video: 'Video URL', image: 'Image URL',
            coordinates: 'Location', x: 'X', y: 'Y', choosePosition: 'Choose position', choosingPosition: 'Click the map…',
            note: 'Note for moderators', submit: 'Send for approval', update: 'Save pending changes', cancelSubmission: 'Cancel submission',
            submitted: 'Contribution sent for approval.', updated: 'Pending contribution updated.', cancelledMessage: 'Submission cancelled.',
            correctionType: 'What do you want to correct?', text: 'Text / region', location: 'Location', imageCorrection: 'Image', other: 'Other',
            imageAction: 'Image action', addImage: 'Add image', reportImage: 'Report existing image', chooseImage: 'Choose image',
            imageProblem: 'Explain what is wrong with this image.', required: 'Check the highlighted required fields.',
            requiredField: 'Required field.', invalidUrl: 'Use a valid http(s) URL.', optional: 'optional',
            duplicatePending: 'You already have a pending correction for this marker. Open My contributions to edit it.',
            signIn: 'Sign in to contribute.', usernameRequired: 'Your account needs a @username before you can contribute.', loadError: 'Could not load your contributions.', saveError: 'Could not save the contribution.',
            reviewNote: 'Moderator note', revisions: 'versions', editableHint: 'You can edit this while it is pending. After approval, future changes require a new suggestion.',
            preview: 'Live preview', noContributions: 'You have no contributions yet.', currentMarker: 'Marker', status: 'Status',
            correctionHelp: 'Nothing changes on the official map until a moderator approves this suggestion.',
            newHelp: 'New markers are reviewed before they become public.', moderatorNewHelp: 'As a moderator, your contribution is published immediately.', moderatorSubmit: 'Publish contribution', moderatorSubmitted: 'Contribution published.', openMine: 'View my contributions'
        },
        pt: {
            title: 'Contribuição da comunidade', addMarker: 'Adicionar marcador', myContributions: 'As minhas contribuições',
            suggestCorrection: 'Sugerir correção', pending: 'Pendente', approved: 'Aprovada', rejected: 'Rejeitada', cancelled: 'Cancelada',
            editPending: 'Editar submissão pendente', close: 'Fechar', refresh: 'Atualizar', refreshing: 'A atualizar…', refreshed: 'Atualizado agora ✓', perPage: 'Por página', page: 'Página', newContribution: 'Nova contribuição',
            layer: 'Camada do mapa', type: 'Tipo', category: 'Categoria', chooseCategory: 'Escolhe uma categoria…', titleEn: 'Título — EN', titlePt: 'Título — PT',
            region: 'Região', descriptionEn: 'Descrição — EN', descriptionPt: 'Descrição — PT', video: 'URL do vídeo', image: 'URL da imagem',
            coordinates: 'Localização', x: 'X', y: 'Y', choosePosition: 'Escolher posição', choosingPosition: 'Clica no mapa…',
            note: 'Nota para a moderação', submit: 'Enviar para aprovação', update: 'Guardar alterações pendentes', cancelSubmission: 'Cancelar submissão',
            submitted: 'Contribuição enviada para aprovação.', updated: 'Contribuição pendente atualizada.', cancelledMessage: 'Submissão cancelada.',
            correctionType: 'O que queres corrigir?', text: 'Texto / região', location: 'Localização', imageCorrection: 'Imagem', other: 'Outro',
            imageAction: 'Ação da imagem', addImage: 'Adicionar imagem', reportImage: 'Reportar imagem existente', chooseImage: 'Escolher imagem',
            imageProblem: 'Explica o problema desta imagem.', required: 'Revê os campos obrigatórios assinalados.',
            requiredField: 'Campo obrigatório.', invalidUrl: 'Usa um URL http(s) válido.', optional: 'opcional',
            duplicatePending: 'Já tens uma alteração pendente para este marcador. Abre As minhas contribuições para a editares.',
            signIn: 'Inicia sessão para contribuir.', usernameRequired: 'A tua conta precisa de um @username antes de poderes contribuir.', loadError: 'Não foi possível carregar as tuas contribuições.', saveError: 'Não foi possível guardar a contribuição.',
            reviewNote: 'Nota da moderação', revisions: 'versões', editableHint: 'Podes editar enquanto estiver pendente. Depois de aprovada, futuras alterações precisam de uma nova sugestão.',
            preview: 'Pré-visualização', noContributions: 'Ainda não tens contribuições.', currentMarker: 'Marcador', status: 'Estado',
            correctionHelp: 'Nada muda no mapa oficial até um moderador aprovar esta sugestão.',
            newHelp: 'Os marcadores novos são revistos antes de ficarem públicos.', moderatorNewHelp: 'Como moderador, a tua contribuição é publicada imediatamente.', moderatorSubmit: 'Publicar contribuição', moderatorSubmitted: 'Contribuição publicada.', openMine: 'Ver as minhas contribuições'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let isModerator = $derived(userRole === 'moderator');
    let canEditPortuguese = $derived(userRole === 'moderator' || userRole === 'admin');
    let submissions = $state([]);
    let submissionsTotal = $state(0);
    let submissionsPage = $state(1);
    let submissionsPageSize = $state(10);
    let loading = $state(false);
    let refreshFeedback = $state('');
    let refreshTimer;
    let saving = $state(false);
    let errorMessage = $state('');
    let successMessage = $state('');
    let view = $state('form');
    let editingSubmissionId = $state(null);
    let submissionType = $state('create');
    let correctionKind = $state('text');
    let targetMarker = $state(null);
    let mapLayer = $state('surface');
    let categoryGroupId = $state('');
    let categoryId = $state('');
    let titleEn = $state('');
    let titlePt = $state('');
    let regionId = $state('');
    let descriptionEn = $state('');
    let descriptionPt = $state('');
    let videoUrl = $state('');
    let imageUrl = $state('');
    let imageAction = $state('add');
    let targetImageId = $state('');
    let coordinateX = $state('');
    let coordinateY = $state('');
    let positionBackup = null;
    let note = $state('');
    let contentItems = $state([]);
    let fieldErrors = $state({});
    let duplicatePendingId = $state(null);
    let checkingDuplicate = $state(false);
    let lastRequestRevision = null;
    let lastPointRevision = null;
    let focusedSubmissionId = $state(null);

    let sortedGroups = $derived(
        [...categoryGroups].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );
    let sortedCategories = $derived(
        Object.values(categories).slice().sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );
    let filteredCategories = $derived(
        sortedCategories.filter((category) => !categoryGroupId || category.group === categoryGroupId)
    );
    let sortedLayers = $derived(
        Object.values(mapDefinitions).slice().sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );
    let pending = $derived(submissions.filter((item) => item.status === 'pending'));
    let previous = $derived(submissions.filter((item) => item.status !== 'pending'));
    let submissionsPageCount = $derived(Math.max(1, Math.ceil(submissionsTotal / submissionsPageSize)));

    function visibleSubmissionPages() {
        const maxVisible = 5;
        let start = Math.max(1, submissionsPage - Math.floor(maxVisible / 2));
        let end = Math.min(submissionsPageCount, start + maxVisible - 1);
        start = Math.max(1, end - maxVisible + 1);
        return Array.from({ length: end - start + 1 }, (_, index) => start + index);
    }

    function localisedLabel(item) {
        return item?.label?.[language] ?? item?.label?.en ?? item?.label?.pt ?? item?.id ?? '';
    }

    function localisedMarkerTitle(marker) {
        return marker?.title?.[language] ?? marker?.title?.en ?? marker?.title?.pt ?? marker?.slug ?? '';
    }

    function clearMessages() {
        errorMessage = '';
        successMessage = '';
        fieldErrors = {};
    }

    function clearFieldError(name) {
        if (!fieldErrors[name]) return;
        const next = { ...fieldErrors };
        delete next[name];
        fieldErrors = next;
        if (!Object.keys(next).length) errorMessage = '';
    }

    function resetForm() {
        editingSubmissionId = null;
        submissionType = 'create';
        correctionKind = 'text';
        targetMarker = null;
        mapLayer = sortedLayers[0]?.id ?? 'surface';
        categoryGroupId = sortedGroups[0]?.id ?? '';
        categoryId = '';
        titleEn = '';
        titlePt = '';
        regionId = '';
        descriptionEn = '';
        descriptionPt = '';
        videoUrl = '';
        imageUrl = '';
        imageAction = 'add';
        targetImageId = '';
        coordinateX = '';
        coordinateY = '';
        positionBackup = null;
        note = '';
        contentItems = [];
        duplicatePendingId = null;
        checkingDuplicate = false;
        onPositionModeChange(false);
        onPreview(null, { clear: true });
        clearMessages();
    }

    function openCreate() {
        resetForm();
        view = 'form';
        submissionType = 'create';
    }

    async function openCorrection(marker) {
        resetForm();
        view = 'form';
        submissionType = 'correction';
        correctionKind = 'text';
        targetMarker = marker;
        mapLayer = marker?.mapLayer ?? 'surface';
        categoryId = marker?.categoryId ?? '';
        categoryGroupId = categories[marker?.categoryId]?.group ?? sortedGroups[0]?.id ?? '';
        titleEn = marker?.title?.en ?? '';
        titlePt = marker?.title?.pt ?? '';
        regionId = marker?.regionId ?? '';
        descriptionEn = marker?.description?.en ?? '';
        descriptionPt = marker?.description?.pt ?? '';
        videoUrl = marker?.videoUrl ?? '';
        coordinateX = marker?.coordinates?.[1] == null ? '' : String(marker.coordinates[1]);
        coordinateY = marker?.coordinates?.[0] == null ? '' : String(marker.coordinates[0]);

        if (!marker?.databaseId || !userId) return;

        checkingDuplicate = true;
        try {
            duplicatePendingId = await findPendingMarkerCorrection({
                supabase: getSupabaseBrowserClient(),
                gameId,
                userId,
                markerId: marker.databaseId
            });
            if (duplicatePendingId !== null) errorMessage = t.duplicatePending;
        } catch (error) {
            console.warn('DeepMap pending correction check:', error);
        } finally {
            checkingDuplicate = false;
        }
    }

    async function refreshSubmissions({ manual = false } = {}) {
        if (!userId || loading) return;
        loading = true;
        errorMessage = '';
        if (manual) {
            refreshFeedback = '';
            if (refreshTimer) clearTimeout(refreshTimer);
        }
        try {
            const result = await loadMyMarkerSubmissionsPage({
                supabase: getSupabaseBrowserClient(),
                gameId,
                limit: submissionsPageSize,
                offset: (submissionsPage - 1) * submissionsPageSize
            });
            submissions = result.items;
            submissionsTotal = result.total;
            if (submissionsPage > submissionsPageCount) {
                submissionsPage = submissionsPageCount;
                const retry = await loadMyMarkerSubmissionsPage({
                    supabase: getSupabaseBrowserClient(),
                    gameId,
                    limit: submissionsPageSize,
                    offset: (submissionsPage - 1) * submissionsPageSize
                });
                submissions = retry.items;
                submissionsTotal = retry.total;
            }
            focusedSubmissionId = focusSubmissionId == null ? null : Number(focusSubmissionId);
            if (focusedSubmissionId !== null && !submissions.some((item) => item.id === focusedSubmissionId)) {
                const { data: focusedRow, error: focusedError } = await getSupabaseBrowserClient()
                    .from('marker_submissions')
                    .select('id, game_id, marker_id, submission_type, correction_kind, status, submitted_by, payload, note, reviewed_by, reviewed_at, review_note, created_at, updated_at')
                    .eq('id', focusedSubmissionId)
                    .eq('submitted_by', userId)
                    .maybeSingle();
                if (!focusedError && focusedRow) submissions = [normaliseSubmission({ ...focusedRow, revision_count: 0, total_count: submissionsTotal }), ...submissions];
            }
            if (focusedSubmissionId !== null) {
                setTimeout(() => document.getElementById(`contribution-${focusedSubmissionId}`)?.scrollIntoView({ block: 'center', behavior: 'smooth' }), 60);
            }
            if (manual) {
                refreshFeedback = t.refreshed;
                refreshTimer = setTimeout(() => { refreshFeedback = ''; }, 2200);
            }
        } catch (error) {
            console.error('DeepMap community submissions:', error);
            errorMessage = t.loadError;
        } finally {
            loading = false;
        }
    }

    async function handleSubmissionsPageSizeChange() {
        submissionsPage = 1;
        await tick();
        await refreshSubmissions();
    }

    async function goSubmissionsPage(next) {
        if (next < 1 || next > submissionsPageCount || next === submissionsPage) return;
        submissionsPage = next;
        await refreshSubmissions();
    }

    function payloadForCurrentForm() {
        if (submissionType === 'create') {
            return {
                map_layer: mapLayer,
                category_id: categoryId,
                title_en: titleEn.trim(),
                ...(canEditPortuguese ? { title_pt: titlePt.trim() || null } : {}),
                region_id: regionId.trim(),
                description_en: descriptionEn.trim(),
                ...(canEditPortuguese ? { description_pt: descriptionPt.trim() || null } : {}),
                video_url: videoUrl.trim(),
                image_url: imageUrl.trim(),
                coordinate_x: Number(coordinateX),
                coordinate_y: Number(coordinateY),
                content_items: serialiseMarkerContentItems(contentItems)
            };
        }

        if (correctionKind === 'text') {
            return {
                category_id: targetMarker?.categoryId ?? null,
                map_layer: targetMarker?.mapLayer ?? 'surface',
                marker_title: localisedMarkerTitle(targetMarker),
                title_en: titleEn.trim(),
                ...(canEditPortuguese ? { title_pt: titlePt.trim() || null } : {}),
                region_id: regionId.trim(),
                description_en: descriptionEn.trim(),
                ...(canEditPortuguese ? { description_pt: descriptionPt.trim() || null } : {}),
                video_url: videoUrl.trim()
            };
        }

        if (correctionKind === 'location') {
            return {
                coordinate_x: Number(coordinateX),
                coordinate_y: Number(coordinateY),
                category_id: targetMarker?.categoryId ?? null,
                map_layer: targetMarker?.mapLayer ?? 'surface',
                marker_title: localisedMarkerTitle(targetMarker)
            };
        }

        if (correctionKind === 'image') {
            return {
                category_id: targetMarker?.categoryId ?? null,
                map_layer: targetMarker?.mapLayer ?? 'surface',
                marker_title: localisedMarkerTitle(targetMarker),
                image_action: imageAction,
                image_url: imageAction === 'add' ? imageUrl.trim() : '',
                target_image_id: imageAction === 'report' ? (targetImageId || null) : null
            };
        }

        return {};
    }

    function hasCoordinateValue(value) {
        return String(value ?? '').trim() !== '' && Number.isFinite(Number(value));
    }

    function validate() {
        const errors = {};

        if (submissionType === 'create') {
            if (!mapLayer) errors.layer = t.requiredField;
            if (!categoryId) errors.category = t.requiredField;
            if (!titleEn.trim()) errors.titleEn = t.requiredField;
            if (!hasCoordinateValue(coordinateX)) errors.coordinateX = t.requiredField;
            if (!hasCoordinateValue(coordinateY)) errors.coordinateY = t.requiredField;
            if (videoUrl.trim() && !normaliseHttpUrl(videoUrl)) errors.video = t.invalidUrl;
            if (imageUrl.trim() && !normaliseHttpUrl(imageUrl)) errors.image = t.invalidUrl;
        }

        if (submissionType === 'correction' && correctionKind === 'text') {
            if (videoUrl.trim() && !normaliseHttpUrl(videoUrl)) errors.video = t.invalidUrl;
        }

        if (submissionType === 'correction' && correctionKind === 'location') {
            if (!hasCoordinateValue(coordinateX)) errors.coordinateX = t.requiredField;
            if (!hasCoordinateValue(coordinateY)) errors.coordinateY = t.requiredField;
        }

        if (submissionType === 'correction' && correctionKind === 'image') {
            if (imageAction === 'add') {
                if (!imageUrl.trim()) errors.image = t.requiredField;
                else if (!normaliseHttpUrl(imageUrl)) errors.image = t.invalidUrl;
            }
            if (imageAction === 'report' && !targetImageId) errors.targetImage = t.requiredField;
        }

        if (submissionType === 'correction' && correctionKind === 'other' && !note.trim()) {
            errors.note = t.requiredField;
        }

        fieldErrors = errors;
        return Object.keys(errors).length ? t.required : '';
    }

    async function saveSubmission() {
        if (!userId || saving) return;
        clearMessages();
        const validation = validate();
        if (validation) {
            errorMessage = validation;
            return;
        }

        if (submissionType === 'correction' && editingSubmissionId === null && targetMarker?.databaseId) {
            try {
                const pendingId = await findPendingMarkerCorrection({
                    supabase: getSupabaseBrowserClient(),
                    gameId,
                    userId,
                    markerId: targetMarker.databaseId
                });
                if (pendingId !== null) {
                    duplicatePendingId = pendingId;
                    errorMessage = t.duplicatePending;
                    return;
                }
            } catch (error) {
                console.warn('DeepMap pending correction recheck:', error);
            }
        }

        saving = true;
        try {
            const supabase = getSupabaseBrowserClient();
            await ensureContributorProfile({ supabase });
            const payload = payloadForCurrentForm();

            if (editingSubmissionId === null) {
                await createMarkerSubmission({
                    supabase,
                    gameId,
                    userId,
                    type: submissionType,
                    markerId: submissionType === 'correction' ? targetMarker?.databaseId ?? null : null,
                    correctionKind: submissionType === 'correction' ? correctionKind : null,
                    payload,
                    note
                });
                successMessage = isModerator ? t.moderatorSubmitted : t.submitted;
            } else {
                await updateMarkerSubmission({
                    supabase,
                    submissionId: editingSubmissionId,
                    correctionKind: submissionType === 'correction' ? correctionKind : null,
                    payload,
                    note
                });
                successMessage = t.updated;
            }

            onPositionModeChange(false);
            onPreview(null, { clear: true });
            await refreshSubmissions();
            await onSubmitted();
            view = 'mine';
        } catch (error) {
            console.error('DeepMap save community submission:', error);
            errorMessage = error?.code === '23505' ? t.duplicatePending : (String(error?.message ?? error).includes('USERNAME_REQUIRED') ? t.usernameRequired : t.saveError);
        } finally {
            saving = false;
        }
    }

    function loadSubmission(item) {
        if (!item || item.status !== 'pending') return;
        resetForm();
        editingSubmissionId = item.id;
        submissionType = item.type;
        correctionKind = item.correctionKind ?? 'text';
        note = item.note ?? '';
        const p = item.payload ?? {};
        mapLayer = p.map_layer ?? sortedLayers[0]?.id ?? 'surface';
        categoryId = p.category_id ?? '';
        titleEn = p.title_en ?? '';
        titlePt = p.title_pt ?? '';
        regionId = p.region_id ?? '';
        descriptionEn = p.description_en ?? '';
        descriptionPt = p.description_pt ?? '';
        videoUrl = p.video_url ?? '';
        imageUrl = p.image_url ?? '';
        imageAction = p.image_action ?? 'add';
        targetImageId = p.target_image_id == null ? '' : String(p.target_image_id);
        coordinateX = p.coordinate_x == null ? '' : String(p.coordinate_x);
        coordinateY = p.coordinate_y == null ? '' : String(p.coordinate_y);
        categoryGroupId = categories[categoryId]?.group ?? sortedGroups[0]?.id ?? '';
        contentItems = Array.isArray(p.content_items)
            ? p.content_items.map((item) => ({
                type: item?.type ?? 'note',
                textEn: item?.text_en ?? '',
                textPt: item?.text_pt ?? ''
            }))
            : [];

        if (item.markerId) {
            targetMarker = requestMarker?.databaseId === item.markerId
                ? requestMarker
                : {
                    databaseId: item.markerId,
                    categoryId: p.category_id ?? null,
                    mapLayer: p.map_layer ?? 'surface',
                    title: { en: p.marker_title ?? '', pt: p.marker_title ?? '' }
                };
        }
        view = 'form';
    }

    async function cancelCurrentSubmission() {
        if (!editingSubmissionId || saving) return;
        if (!window.confirm(language === 'pt' ? 'Cancelar esta submissão?' : 'Cancel this submission?')) return;
        saving = true;
        clearMessages();
        try {
            await cancelMarkerSubmission({
                supabase: getSupabaseBrowserClient(),
                submissionId: editingSubmissionId
            });
            await refreshSubmissions();
            resetForm();
            view = 'mine';
            successMessage = t.cancelledMessage;
            await onSubmitted();
        } catch (error) {
            console.error('DeepMap cancel submission:', error);
            errorMessage = t.saveError;
        } finally {
            saving = false;
        }
    }

    function handleCategoryGroupChange() {
        if (categoryId && categories[categoryId]?.group !== categoryGroupId) categoryId = '';
        clearFieldError('category');
    }

    function beginPositionSelection() {
        if (positionModeActive || saving) return;
        positionBackup = { x: coordinateX, y: coordinateY };
        onPositionModeChange(true);
    }

    export function confirmPositionSelection() {
        if (!positionModeActive) return;
        positionBackup = null;
        onPositionModeChange(false);
    }

    export function cancelPositionSelection() {
        if (!positionModeActive) return;
        if (positionBackup) {
            coordinateX = positionBackup.x;
            coordinateY = positionBackup.y;
        }
        positionBackup = null;
        onPositionModeChange(false);
    }

    function togglePosition() {
        if (positionModeActive) cancelPositionSelection();
        else beginPositionSelection();
    }

    $effect(() => {
        if (!active || requestRevision === lastRequestRevision) return;
        lastRequestRevision = requestRevision;
        if (requestMode === 'mine') {
            view = 'mine';
            resetForm();
            void refreshSubmissions();
        } else if (requestMode === 'correction') {
            void openCorrection(requestMarker);
        } else {
            openCreate();
        }
    });

    $effect(() => {
        const revision = point?.revision ?? null;
        if (!active || revision === null || revision === lastPointRevision) return;
        lastPointRevision = revision;
        coordinateX = String(point.x);
        coordinateY = String(point.y);
    });

    // Map preview is intentionally lightweight: only the in-progress marker is touched.
    $effect(() => {
        if (!active || view !== 'form') return;
        const shouldPreview = submissionType === 'create' || correctionKind === 'location';
        if (!shouldPreview) {
            onPreview(null, { clear: true });
            return;
        }
        if (!hasCoordinateValue(coordinateX) || !hasCoordinateValue(coordinateY)) {
            onPreview(null, { clear: true });
            return;
        }
        const x = Number(coordinateX);
        const y = Number(coordinateY);
        if (!Number.isFinite(x) || !Number.isFinite(y)) {
            onPreview(null, { clear: true });
            return;
        }
        onPreview({
            coordinateX: x,
            coordinateY: y,
            categoryId: submissionType === 'create' ? categoryId : targetMarker?.categoryId,
            mapLayer: submissionType === 'create' ? mapLayer : targetMarker?.mapLayer,
            previewOnly: true
        });
    });
</script>

{#if active}
    <section class:position-picking={positionModeActive} class:mobile-position-flow={mobilePositionFlow} class="community-panel" aria-label={t.title}>
        <header class="community-heading">
            <div>
                <span class="eyebrow">DeepMap</span>
                <strong>{view === 'mine' ? t.myContributions : submissionType === 'create' ? t.addMarker : t.suggestCorrection}</strong>
            </div>
            <button class="icon-button" type="button" onclick={onClose} aria-label={t.close}>✕</button>
        </header>

        {#if !userId}
            <p class="message error">{t.signIn}</p>
        {:else}
            <nav class="community-tabs">
                <button class:active={view === 'form' && submissionType === 'create'} type="button" onclick={openCreate}>{t.addMarker}</button>
                <button class:active={view === 'mine'} type="button" onclick={() => { view = 'mine'; submissionsPage = 1; void refreshSubmissions(); }}>{t.myContributions}</button>
            </nav>

            {#if errorMessage}<p class="message error">{errorMessage}</p>{/if}
            {#if successMessage}<p class="message success">{successMessage}</p>{/if}

            {#if view === 'mine'}
                <div class="mine-heading">
                    <p>{t.editableHint}</p>
                    <div class="mine-actions">
                        <label class="page-size"><span>{t.perPage}</span><select bind:value={submissionsPageSize} onchange={handleSubmissionsPageSizeChange} disabled={loading}><option value={10}>10</option><option value={20}>20</option><option value={50}>50</option></select></label>
                        <div class="refresh-control"><button class="small-button" type="button" onclick={() => refreshSubmissions({ manual: true })} disabled={loading}>{loading?t.refreshing:t.refresh}</button>{#if refreshFeedback}<small class="refresh-feedback" role="status">{refreshFeedback}</small>{/if}</div>
                    </div>
                </div>

                {#if loading && !submissions.length}
                    <p class="muted">…</p>
                {:else if !submissions.length}
                    <p class="muted">{t.noContributions}</p>
                {:else}
                    <div class="submission-list">
                        {#each pending as item (item.id)}
                            <button class="submission-card pending" type="button" onclick={() => loadSubmission(item)}>
                                <span><b>#{item.id}</b> · {item.type === 'create' ? t.addMarker : t.suggestCorrection}</span>
                                <small>{t.pending} · {item.revisionCount} {t.revisions}</small>
                            </button>
                        {/each}
                        {#each previous as item (item.id)}
                            <article id={`contribution-${item.id}`} class:focused={focusedSubmissionId === item.id} class="submission-card readonly">
                                <span><b>#{item.id}</b> · {item.type === 'create' ? t.addMarker : t.suggestCorrection}</span>
                                <small>{item.status === 'approved' ? t.approved : item.status === 'rejected' ? t.rejected : t.cancelled}</small>
                                {#if item.reviewNote}<small>{t.reviewNote}: {item.reviewNote}</small>{/if}
                            </article>
                        {/each}
                    </div>
                    {#if submissionsTotal > submissionsPageSize}
                        <nav class="pagination" aria-label={`${t.page} ${submissionsPage}`}><button type="button" onclick={()=>goSubmissionsPage(submissionsPage-1)} disabled={loading||submissionsPage<=1}>‹</button>{#each visibleSubmissionPages() as p}<button class:active={p===submissionsPage} type="button" onclick={()=>goSubmissionsPage(p)} disabled={loading}>{p}</button>{/each}<button type="button" onclick={()=>goSubmissionsPage(submissionsPage+1)} disabled={loading||submissionsPage>=submissionsPageCount}>›</button></nav>
                    {/if}
                {/if}
            {:else}
                <p class="help">{submissionType === 'create' ? (isModerator ? t.moderatorNewHelp : t.newHelp) : t.correctionHelp}</p>

                {#if submissionType === 'correction'}
                    <div class="target-marker"><span>{t.currentMarker}</span><strong>{localisedMarkerTitle(requestMarker ?? targetMarker)}</strong></div>
                    <div class="correction-types" role="group" aria-label={t.correctionType}>
                        <button class:active={correctionKind === 'text'} type="button" onclick={() => correctionKind = 'text'}>{t.text}</button>
                        <button class:active={correctionKind === 'location'} type="button" onclick={() => correctionKind = 'location'}>{t.location}</button>
                        <button class:active={correctionKind === 'image'} type="button" onclick={() => correctionKind = 'image'}>{t.imageCorrection}</button>
                        <button class:active={correctionKind === 'other'} type="button" onclick={() => correctionKind = 'other'}>{t.other}</button>
                    </div>
                {/if}

                {#if submissionType === 'create'}
                    <div class="grid two">
                        <label class:invalid={Boolean(fieldErrors.layer)}>
                            <span>{t.layer} *</span>
                            <select bind:value={mapLayer} onchange={() => clearFieldError('layer')} disabled={saving}>
                                {#each sortedLayers as layer}<option value={layer.id}>{localisedLabel(layer)}</option>{/each}
                            </select>
                            {#if fieldErrors.layer}<small class="field-error">{fieldErrors.layer}</small>{/if}
                        </label>
                        <label>
                            <span>{t.type}</span>
                            <select bind:value={categoryGroupId} onchange={handleCategoryGroupChange} disabled={saving}>
                                {#each sortedGroups as group}<option value={group.id}>{localisedLabel(group)}</option>{/each}
                            </select>
                        </label>
                    </div>
                    <label class:invalid={Boolean(fieldErrors.category)}>
                        <span>{t.category} *</span>
                        <select bind:value={categoryId} onchange={() => clearFieldError('category')} disabled={saving}>
                            <option value="">{t.chooseCategory}</option>
                            {#each filteredCategories as category}<option value={category.id}>{localisedLabel(category)}</option>{/each}
                        </select>
                        {#if fieldErrors.category}<small class="field-error">{fieldErrors.category}</small>{/if}
                    </label>

                    <fieldset class="location-box">
                        <legend>{t.coordinates} *</legend>
                        <div class="coordinate-row">
                            <span>{t.x} *</span>
                            <CoordinateStepper axis="x" bind:value={coordinateX} invalid={Boolean(fieldErrors.coordinateX)} onValueChange={() => clearFieldError('coordinateX')} disabled={saving} />
                            {#if fieldErrors.coordinateX}<small class="field-error">{fieldErrors.coordinateX}</small>{/if}
                        </div>
                        <div class="coordinate-row">
                            <span>{t.y} *</span>
                            <CoordinateStepper axis="y" bind:value={coordinateY} invalid={Boolean(fieldErrors.coordinateY)} onValueChange={() => clearFieldError('coordinateY')} disabled={saving} />
                            {#if fieldErrors.coordinateY}<small class="field-error">{fieldErrors.coordinateY}</small>{/if}
                        </div>
                        <button class:active={positionModeActive} class="position-button" type="button" onclick={togglePosition} disabled={saving}>{positionModeActive ? t.choosingPosition : t.choosePosition}</button>
                    </fieldset>
                {/if}

                {#if submissionType === 'create' || correctionKind === 'text'}
                    <div class:single={!canEditPortuguese} class="grid two">
                        <label class:invalid={Boolean(fieldErrors.titleEn)}>
                            <span>{t.titleEn}{submissionType === 'create' ? ' *' : ` (${t.optional})`}</span>
                            <input bind:value={titleEn} oninput={() => clearFieldError('titleEn')} disabled={saving} />
                            {#if fieldErrors.titleEn}<small class="field-error">{fieldErrors.titleEn}</small>{/if}
                        </label>
                        {#if canEditPortuguese}
                            <label><span>{t.titlePt} ({t.optional})</span><input bind:value={titlePt} disabled={saving} /></label>
                        {/if}
                    </div>
                    <label><span>{t.region} ({t.optional})</span><input bind:value={regionId} disabled={saving} /></label>
                    <label><span>{t.descriptionEn} ({t.optional})</span><textarea rows="3" bind:value={descriptionEn} disabled={saving}></textarea></label>
                    {#if canEditPortuguese}
                        <label><span>{t.descriptionPt} ({t.optional})</span><textarea rows="3" bind:value={descriptionPt} disabled={saving}></textarea></label>
                    {/if}
                    <label class:invalid={Boolean(fieldErrors.video)}>
                        <span>{t.video} ({t.optional})</span>
                        <input type="url" bind:value={videoUrl} oninput={() => clearFieldError('video')} placeholder="https://…" disabled={saving} />
                        {#if fieldErrors.video}<small class="field-error">{fieldErrors.video}</small>{/if}
                    </label>
                    {#if submissionType === 'create'}
                        <label class:invalid={Boolean(fieldErrors.image)}>
                            <span>{t.image} ({t.optional})</span>
                            <input type="url" bind:value={imageUrl} oninput={() => clearFieldError('image')} placeholder="https://…" disabled={saving} />
                            {#if fieldErrors.image}<small class="field-error">{fieldErrors.image}</small>{/if}
                        </label>
                    {/if}
                {/if}

                {#if submissionType === 'create'}
                    <MarkerContentEditor {language} bind:value={contentItems} disabled={saving} showPortuguese={canEditPortuguese} />
                {/if}

                {#if submissionType === 'correction' && correctionKind === 'location'}
                    <fieldset class="location-box">
                        <legend>{t.coordinates} *</legend>
                        <div class="coordinate-row">
                            <span>{t.x} *</span>
                            <CoordinateStepper axis="x" bind:value={coordinateX} invalid={Boolean(fieldErrors.coordinateX)} onValueChange={() => clearFieldError('coordinateX')} disabled={saving} />
                            {#if fieldErrors.coordinateX}<small class="field-error">{fieldErrors.coordinateX}</small>{/if}
                        </div>
                        <div class="coordinate-row">
                            <span>{t.y} *</span>
                            <CoordinateStepper axis="y" bind:value={coordinateY} invalid={Boolean(fieldErrors.coordinateY)} onValueChange={() => clearFieldError('coordinateY')} disabled={saving} />
                            {#if fieldErrors.coordinateY}<small class="field-error">{fieldErrors.coordinateY}</small>{/if}
                        </div>
                        <button class:active={positionModeActive} class="position-button" type="button" onclick={togglePosition} disabled={saving}>{positionModeActive ? t.choosingPosition : t.choosePosition}</button>
                    </fieldset>
                {/if}

                {#if submissionType === 'correction' && correctionKind === 'image'}
                    <label><span>{t.imageAction}</span><select bind:value={imageAction} disabled={saving}><option value="add">{t.addImage}</option><option value="report">{t.reportImage}</option></select></label>
                    {#if imageAction === 'add'}
                        <label class:invalid={Boolean(fieldErrors.image)}>
                            <span>{t.image} *</span>
                            <input type="url" bind:value={imageUrl} oninput={() => clearFieldError('image')} placeholder="https://…" disabled={saving} />
                            {#if fieldErrors.image}<small class="field-error">{fieldErrors.image}</small>{/if}
                        </label>
                    {:else}
                        <label class:invalid={Boolean(fieldErrors.targetImage)}>
                            <span>{t.chooseImage} *</span>
                            <select bind:value={targetImageId} onchange={() => clearFieldError('targetImage')} disabled={saving}><option value="">—</option>{#each (requestMarker?.images ?? []) as image}<option value={String(image.id)}>{image.url ?? image.imageRef ?? `#${image.id}`}</option>{/each}</select>
                            {#if fieldErrors.targetImage}<small class="field-error">{fieldErrors.targetImage}</small>{/if}
                        </label>
                    {/if}
                {/if}

                <label class:invalid={Boolean(fieldErrors.note)}>
                    <span>{t.note}{submissionType === 'correction' && correctionKind === 'other' ? ' *' : ` (${t.optional})`}</span>
                    <textarea rows="2" bind:value={note} oninput={() => clearFieldError('note')} disabled={saving}></textarea>
                    {#if fieldErrors.note}<small class="field-error">{fieldErrors.note}</small>{/if}
                </label>

                <div class="actions">
                    <button class="primary" type="button" onclick={saveSubmission} disabled={saving || checkingDuplicate || (submissionType === 'correction' && editingSubmissionId === null && duplicatePendingId !== null)}>{editingSubmissionId === null ? (isModerator ? t.moderatorSubmit : t.submit) : t.update}</button>
                    {#if editingSubmissionId !== null}<button class="danger" type="button" onclick={cancelCurrentSubmission} disabled={saving}>{t.cancelSubmission}</button>{/if}
                    {#if submissionType === 'correction' && editingSubmissionId === null}<button type="button" onclick={onClose} disabled={saving}>{t.close}</button>{/if}
                </div>
            {/if}
        {/if}
    </section>
{/if}

<style>
    .community-panel{position:fixed;top:118px;right:18px;z-index:1300;width:min(430px,calc(100vw - 36px));max-height:calc(100vh - 140px);overflow:auto;padding:14px;border:1px solid #34343e;border-radius:12px;background:rgba(12,12,15,.98);box-shadow:0 18px 48px rgba(0,0,0,.48);color:#f0f0f2;touch-action:pan-y;overscroll-behavior:contain;-webkit-overflow-scrolling:touch}
    .community-heading,.mine-heading,.actions{display:flex;align-items:center;justify-content:space-between;gap:10px}.community-heading{position:sticky;top:-14px;z-index:5;margin:-14px -14px 12px;padding:14px;background:rgba(12,12,15,.985);border-bottom:1px solid #2b2b33}.community-heading div{display:grid;gap:2px}.eyebrow{color:#c8a355;font-size:.7rem;font-weight:800;text-transform:uppercase;letter-spacing:.08em}.icon-button,.small-button,.community-tabs button,.correction-types button,.position-button,.actions button{border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd;cursor:pointer}.icon-button{width:34px;height:34px}.small-button,.position-button,.actions button{padding:8px 11px}.community-tabs,.correction-types{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-bottom:12px}.correction-types{grid-template-columns:repeat(2,1fr)}.community-tabs button,.correction-types button{padding:8px}.community-tabs button.active,.correction-types button.active,.position-button.active{border-color:#c8a355;color:#f1d58e;background:#211d14}.grid{display:grid;gap:10px}.grid.two{grid-template-columns:1fr 1fr}.grid.two.single{grid-template-columns:1fr}
    label{display:grid;gap:5px;margin:10px 0}label>span,legend{color:#b8b8c0;font-size:.72rem;font-weight:700}input,select,textarea{width:100%;box-sizing:border-box;border:1px solid #34343e;border-radius:8px;background:#0f0f13;color:#eee;padding:9px 10px;font:inherit}textarea{resize:vertical}input:focus,select:focus,textarea:focus{outline:none;border-color:#c8a355;box-shadow:0 0 0 2px rgba(200,163,85,.11)}label.invalid input,label.invalid select,label.invalid textarea,input.invalid{border-color:#c85f67!important;box-shadow:0 0 0 2px rgba(200,95,103,.12)}.field-error{color:#ff9da7;font-size:.68rem;line-height:1.3}
    .mine-heading{display:flex;align-items:flex-end;justify-content:space-between;gap:14px;margin-bottom:16px}.mine-actions{display:flex;align-items:flex-end;gap:12px}.page-size{display:grid;gap:3px;min-width:120px}.page-size span{color:#888;font-size:.62rem;white-space:nowrap}.page-size select{width:100%;padding:7px 26px 7px 8px;border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd}.refresh-control{display:grid;justify-items:end;gap:3px}.refresh-feedback{color:#8fd3a3;font-size:.62rem;font-weight:800;white-space:nowrap}.pagination{display:flex;justify-content:center;gap:5px;flex-wrap:wrap}.pagination button{min-width:32px;height:32px;border:1px solid #3a3a45;border-radius:8px;background:#17171c;color:#ddd;cursor:pointer}.pagination button.active{border-color:#c8a355;background:#211d14;color:#f0d28a}.pagination button:disabled{opacity:.5;cursor:not-allowed}.help,.muted,.mine-heading p{color:#9696a0;font-size:.78rem;line-height:1.4}.message{padding:9px 10px;border-radius:8px;font-size:.8rem}.message.error{background:#2a1518;color:#ffb4bd}.message.success{background:#16251b;color:#b9efc7}.submission-list{display:grid;gap:8px}.submission-card{display:grid;gap:3px;width:100%;padding:10px;border:1px solid #303039;border-radius:9px;background:#121217;color:#eee;text-align:left}.submission-card.pending{cursor:pointer}.submission-card.pending:hover{border-color:#c8a355}.submission-card.focused{border-color:#c8a355;box-shadow:0 0 0 2px rgba(200,163,85,.12);background:#1b1811}.submission-card small{color:#9b9ba5}.target-marker{display:flex;justify-content:space-between;gap:10px;padding:9px 10px;border:1px solid #303039;border-radius:8px;background:#111116}.target-marker span{color:#999}
    .location-box{margin:12px 0;padding:10px;border:1px solid #303039;border-radius:9px;background:rgba(9,9,12,.42)}.coordinate-row{display:grid;grid-template-columns:42px minmax(0,1fr);align-items:center;gap:7px;margin:7px 0}.coordinate-row>.field-error{grid-column:2}
    .actions{justify-content:flex-start;flex-wrap:wrap;margin-top:12px}.actions .primary{border-color:#c8a355;background:#c8a355;color:#111;font-weight:800}.actions .danger{border-color:#6f343b;color:#ffc1c8}.actions button:disabled,.position-button:disabled{opacity:.55;cursor:not-allowed}
    .community-panel.position-picking{display:none}
    @media(max-width:700px){.mine-heading{align-items:stretch;flex-direction:column}.mine-actions{display:grid;grid-template-columns:auto minmax(0,1fr);align-items:end}.refresh-control{justify-items:stretch}.refresh-feedback{text-align:center}.community-panel{top:106px;left:10px;right:10px;width:auto;max-height:calc(100dvh - 120px)}.grid.two{grid-template-columns:1fr}.actions{position:sticky;bottom:-14px;z-index:4;margin:12px -14px -14px;padding:10px 14px;background:rgba(12,12,15,.985);border-top:1px solid #2b2b33}}
</style>
