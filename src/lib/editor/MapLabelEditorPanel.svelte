<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import {
        createEditorMapLabel,
        deleteEditorMapLabel,
        loadEditorMapLabels,
        slugifyMapLabel,
        updateEditorMapLabel
    } from '$lib/editor/map-label-editor.js';

    let {
        gameId,
        language = 'en',
        active = false,
        point = null,
        selectedLabelId = null,
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
            title: 'Zone titles',
            newLabel: 'New zone title',
            existing: 'Existing zone title',
            drafts: 'Drafts',
            published: 'Published',
            chooseDraft: 'Choose a draft…',
            choosePublished: 'Choose a published title…',
            none: 'None yet.',
            newButton: 'New title',
            refresh: 'Refresh',
            layer: 'Layer',
            textEn: 'Text — EN',
            textPt: 'Text — PT',
            x: 'X',
            y: 'Y',
            appearance: 'Appearance',
            fontSize: 'Font size',
            fontWeight: 'Weight',
            color: 'Color',
            opacity: 'Opacity',
            uppercase: 'Uppercase',
            saveDraft: 'Save draft',
            saveChanges: 'Save changes',
            publish: 'Publish',
            moveDraft: 'Move to draft',
            cancelEdit: 'Cancel editing',
            delete: 'Delete',
            saving: 'Saving…',
            deleting: 'Deleting…',
            saved: 'Zone title saved.',
            deleted: 'Zone title deleted.',
            required: 'Fill both texts and valid coordinates.',
            slugError: 'Could not generate a valid slug from the English text.',
            loadError: 'Could not load zone titles.',
            saveError: 'Could not save the zone title.',
            deleteError: 'Could not delete the zone title.',
            confirmDelete: 'Delete this zone title? This cannot be undone.',
            clickMap: 'New title: click the map to choose its position. Existing title: use Change position.',
            changePosition: 'Change position',
            choosingPosition: 'Click the map…',
            showOriginal: 'Show original location',
            showOriginalHelp: 'Useful for fine adjustments.'
        },
        pt: {
            title: 'Títulos de zona',
            newLabel: 'Novo título de zona',
            existing: 'Título de zona existente',
            drafts: 'Rascunhos',
            published: 'Publicados',
            chooseDraft: 'Escolhe um rascunho…',
            choosePublished: 'Escolhe um título publicado…',
            none: 'Ainda não existem.',
            newButton: 'Novo título',
            refresh: 'Atualizar',
            layer: 'Camada',
            textEn: 'Texto — EN',
            textPt: 'Texto — PT',
            x: 'X',
            y: 'Y',
            appearance: 'Aspeto',
            fontSize: 'Tamanho da letra',
            fontWeight: 'Peso',
            color: 'Cor',
            opacity: 'Opacidade',
            uppercase: 'Maiúsculas',
            saveDraft: 'Guardar rascunho',
            saveChanges: 'Guardar alterações',
            publish: 'Publicar',
            moveDraft: 'Passar a rascunho',
            cancelEdit: 'Cancelar edição',
            delete: 'Eliminar',
            saving: 'A guardar…',
            deleting: 'A eliminar…',
            saved: 'Título de zona guardado.',
            deleted: 'Título de zona eliminado.',
            required: 'Preenche os dois textos e coordenadas válidas.',
            slugError: 'Não foi possível gerar um slug válido a partir do texto EN.',
            loadError: 'Não foi possível carregar os títulos de zona.',
            saveError: 'Não foi possível guardar o título de zona.',
            deleteError: 'Não foi possível eliminar o título de zona.',
            confirmDelete: 'Eliminar este título de zona? Esta ação não pode ser anulada.',
            clickMap: 'Novo título: clica no mapa para escolher a posição. Título existente: usa Mudar posição.',
            changePosition: 'Mudar posição',
            choosingPosition: 'Clica no mapa…',
            showOriginal: 'Mostrar localização original',
            showOriginalHelp: 'Útil para pequenos retoques.'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);

    let labels = $state([]);
    let loading = $state(false);
    let saving = $state(false);
    let deleting = $state(false);
    let errorMessage = $state('');
    let successMessage = $state('');
    let loadedOnce = false;
    let lastPointRevision = null;
    let lastSelectedLabelId = null;

    let editingId = $state(null);
    let mapLayer = $state('surface');
    let slug = $state('');
    let textEn = $state('');
    let textPt = $state('');
    let coordinateX = $state('');
    let coordinateY = $state('');
    let fontSize = $state(34);
    let fontWeight = $state(700);
    let color = $state('#E8D7A4');
    let opacity = $state(0.82);
    let uppercase = $state(true);
    let isPublished = $state(false);
    let showOriginalLocation = $state(false);
    let labelMoved = $state(false);

    let sortedLayers = $derived(
        Object.values(mapDefinitions).sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );
    let drafts = $derived(labels.filter((item) => !item.isPublished));
    let published = $derived(labels.filter((item) => item.isPublished));
    let selected = $derived(editingId === null ? null : labels.find((item) => item.id === editingId) ?? null);

    function localisedLabel(item) {
        return item?.label?.[language] ?? item?.label?.en ?? item?.label?.pt ?? item?.id ?? '';
    }

    function clearMessages() {
        errorMessage = '';
        successMessage = '';
    }

    function resetForm({ keepCoordinates = true } = {}) {
        editingId = null;
        mapLayer = sortedLayers[0]?.id ?? 'surface';
        slug = '';
        textEn = '';
        textPt = '';
        fontSize = 34;
        fontWeight = 700;
        color = '#E8D7A4';
        opacity = 0.82;
        uppercase = true;
        isPublished = false;
        if (!keepCoordinates) {
            coordinateX = '';
            coordinateY = '';
        }
        showOriginalLocation = false;
        labelMoved = false;
        clearMessages();
        onSelectionChange(null);
        onPositionModeChange(false);
        onMoveStateChange(false);
        onOriginalVisibilityChange(false);
        if (!keepCoordinates) onPreview(null, { clear: true });
    }

    function loadIntoForm(item) {
        if (!item) return;
        editingId = item.id;
        mapLayer = item.mapLayer;
        slug = item.slug;
        textEn = item.textEn;
        textPt = item.textPt;
        coordinateX = String(item.coordinateX);
        coordinateY = String(item.coordinateY);
        fontSize = item.fontSize;
        fontWeight = item.fontWeight;
        color = item.color;
        opacity = item.opacity;
        uppercase = item.uppercase;
        isPublished = item.isPublished;
        showOriginalLocation = false;
        labelMoved = false;
        clearMessages();
        onPositionModeChange(false);
        onMoveStateChange(false);
        onOriginalVisibilityChange(false);
        onSelectionChange(item.id, [item.coordinateY, item.coordinateX]);
        onPreview(item, { pan: true });
    }

    async function refresh({ preserveSelection = true } = {}) {
        loading = true;
        errorMessage = '';
        const previousId = preserveSelection ? editingId : null;
        try {
            labels = await loadEditorMapLabels({
                supabase: getSupabaseBrowserClient(),
                gameId
            });
            if (previousId !== null) {
                const same = labels.find((item) => item.id === previousId);
                if (same) loadIntoForm(same);
            }
        } catch (error) {
            console.error('DeepMap zone title editor load:', error);
            errorMessage = t.loadError;
        } finally {
            loading = false;
        }
    }

    function choose(event) {
        const value = event.currentTarget.value;
        if (!value) {
            resetForm({ keepCoordinates: true });
            return;
        }
        const item = labels.find((entry) => String(entry.id) === value);
        if (item) loadIntoForm(item);
    }

    function buildInput(nextPublished = isPublished) {
        const nextSlug = slug || slugifyMapLabel(textEn || textPt);
        return {
            mapLayer,
            slug: nextSlug,
            textEn,
            textPt,
            coordinateX: Number(coordinateX),
            coordinateY: Number(coordinateY),
            fontSize: Number(fontSize),
            fontWeight: Number(fontWeight),
            color,
            opacity: Number(opacity),
            uppercase,
            isPublished: nextPublished
        };
    }

    function validate(input) {
        if (!input.textEn.trim() || !input.textPt.trim() || !Number.isFinite(input.coordinateX) || !Number.isFinite(input.coordinateY)) {
            return t.required;
        }
        if (!input.slug) return t.slugError;
        return '';
    }

    function nudgeCoordinateX(delta) {
        coordinateX = String((Number(coordinateX) || 0) + delta);
    }

    function hasCoordinateValue(value) {
        return String(value ?? '').trim() !== '' && Number.isFinite(Number(value));
    }

    function togglePositionMode() {
        if (editingId === null || saving || deleting) return;
        onPositionModeChange(!positionModeActive);
    }

    async function save(nextPublished) {
        if (saving || deleting) return;
        clearMessages();
        const input = buildInput(nextPublished);
        const validation = validate(input);
        if (validation) {
            errorMessage = validation;
            return;
        }
        slug = input.slug;
        saving = true;
        try {
            const supabase = getSupabaseBrowserClient();
            const saved = editingId === null
                ? await createEditorMapLabel({ supabase, gameId, label: input })
                : await updateEditorMapLabel({ supabase, gameId, labelId: editingId, label: input });
            await refresh({ preserveSelection: false });
            resetForm({ keepCoordinates: false });
            successMessage = t.saved;
            await onChanged({ action: 'save-label', label: saved });
        } catch (error) {
            console.error('DeepMap zone title editor save:', error);
            errorMessage = t.saveError;
        } finally {
            saving = false;
        }
    }

    async function remove() {
        if (editingId === null || saving || deleting) return;
        if (!window.confirm(t.confirmDelete)) return;
        deleting = true;
        clearMessages();
        try {
            const deletedId = editingId;
            await deleteEditorMapLabel({
                supabase: getSupabaseBrowserClient(),
                gameId,
                labelId: deletedId
            });
            resetForm({ keepCoordinates: false });
            await refresh({ preserveSelection: false });
            successMessage = t.deleted;
            await onChanged({ action: 'delete-label', labelId: deletedId });
        } catch (error) {
            console.error('DeepMap zone title editor delete:', error);
            errorMessage = t.deleteError;
        } finally {
            deleting = false;
        }
    }

    $effect(() => {
        if (!active || loadedOnce) return;
        loadedOnce = true;
        void refresh({ preserveSelection: false });
    });

    $effect(() => {
        const revision = point?.revision ?? null;
        if (!active || revision === null || revision === lastPointRevision) return;
        lastPointRevision = revision;
        coordinateX = String(point.x);
        coordinateY = String(point.y);
        if (editingId !== null) {
            labelMoved = true;
            onMoveStateChange(true);
            onPositionModeChange(false);
        }
    });

    $effect(() => {
        if (!active) return;

        if (selectedLabelId === null) {
            lastSelectedLabelId = null;
            return;
        }

        if (selectedLabelId === lastSelectedLabelId) return;

        const item = labels.find((entry) => Number(entry.id) === Number(selectedLabelId));
        if (item) {
            lastSelectedLabelId = selectedLabelId;
            loadIntoForm(item);
        }
    });

    $effect(() => {
        if (!active) return;
        if (!hasCoordinateValue(coordinateX) || !hasCoordinateValue(coordinateY)) {
            onPreview(null, { clear: true });
            return;
        }
        const preview = buildInput(isPublished);
        if (!Number.isFinite(preview.coordinateX) || !Number.isFinite(preview.coordinateY)) return;
        onPreview({ ...preview, id: editingId, previewOnly: true }, { pan: false });
    });
</script>

{#if active}
    <section class="label-editor-panel" aria-label={t.title}>
        <div class="panel-heading">
            <div>
                <span class="eyebrow">{t.title}</span>
                <strong>{editingId === null ? t.newLabel : t.existing}</strong>
            </div>
            <button class="small-button" type="button" onclick={() => refresh()} disabled={loading || saving || deleting}>{t.refresh}</button>
        </div>

        <div class="library">
            <div class="library-heading">
                <strong>{t.existing}</strong>
                <button class="small-button" type="button" onclick={() => resetForm({ keepCoordinates: true })} disabled={saving || deleting}>{t.newButton}</button>
            </div>

            <label>
                <span>{t.drafts} ({drafts.length})</span>
                <select onchange={choose} value={selected && !selected.isPublished ? String(selected.id) : ''} disabled={loading || saving || deleting}>
                    <option value="">{drafts.length ? t.chooseDraft : t.none}</option>
                    {#each drafts as item}<option value={String(item.id)}>{item.textEn}</option>{/each}
                </select>
            </label>

            <label>
                <span>{t.published} ({published.length})</span>
                <select onchange={choose} value={selected?.isPublished ? String(selected.id) : ''} disabled={loading || saving || deleting}>
                    <option value="">{published.length ? t.choosePublished : t.none}</option>
                    {#each published as item}<option value={String(item.id)}>{item.textEn}</option>{/each}
                </select>
            </label>
        </div>

        <p class="help">{t.clickMap}</p>

        <label>
            <span>{t.layer}</span>
            <select bind:value={mapLayer} disabled={saving || deleting}>
                {#each sortedLayers as layer}<option value={layer.id}>{localisedLabel(layer)}</option>{/each}
            </select>
        </label>

        <div class="grid two">
            <label><span>{t.textEn}</span><input bind:value={textEn} disabled={saving || deleting} /></label>
            <label><span>{t.textPt}</span><input bind:value={textPt} disabled={saving || deleting} /></label>
        </div>

        <div class="grid two">
            <label>
                <span>{t.x}</span>
                <div class="coordinate-control-x">
                    <button type="button" aria-label="X - 1" onclick={() => nudgeCoordinateX(-1)} disabled={saving || deleting}>←</button>
                    <input type="number" step="1" bind:value={coordinateX} disabled={saving || deleting} />
                    <button type="button" aria-label="X + 1" onclick={() => nudgeCoordinateX(1)} disabled={saving || deleting}>→</button>
                </div>
            </label>
            <label>
                <span>{t.y}</span>
                <input type="number" step="1" bind:value={coordinateY} disabled={saving || deleting} />
            </label>
        </div>

        {#if selected}
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

                {#if labelMoved}
                    <label class="original-location-toggle">
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
            {#if labelMoved && showOriginalLocation}
                <small class="position-help">{t.showOriginalHelp}</small>
            {/if}
        {/if}

        <details class="advanced">
            <summary>{t.appearance}</summary>
            <div class="advanced-body">
                <div class="grid two">
                    <label><span>{t.fontSize}</span><input type="number" min="10" max="160" bind:value={fontSize} disabled={saving || deleting} /></label>
                    <label><span>{t.fontWeight}</span><input type="number" min="100" max="900" step="100" bind:value={fontWeight} disabled={saving || deleting} /></label>
                </div>
                <div class="grid two">
                    <label><span>{t.color}</span><input type="color" bind:value={color} disabled={saving || deleting} /></label>
                    <label><span>{t.opacity}</span><input type="number" min="0" max="1" step="0.05" bind:value={opacity} disabled={saving || deleting} /></label>
                </div>
                <label class="check-row"><input type="checkbox" bind:checked={uppercase} disabled={saving || deleting} /><span>{t.uppercase}</span></label>
            </div>
        </details>

        <div class="actions">
            {#if isPublished}
                <button class="primary" type="button" onclick={() => save(true)} disabled={saving || deleting}>{saving ? t.saving : t.saveChanges}</button>
                <button class="secondary" type="button" onclick={() => save(false)} disabled={saving || deleting}>{t.moveDraft}</button>
            {:else}
                <button class="secondary" type="button" onclick={() => save(false)} disabled={saving || deleting}>{saving ? t.saving : t.saveDraft}</button>
                <button class="primary" type="button" onclick={() => save(true)} disabled={saving || deleting}>{saving ? t.saving : t.publish}</button>
            {/if}
            {#if editingId !== null}
                <button class="secondary" type="button" onclick={() => resetForm({ keepCoordinates: false })} disabled={saving || deleting}>{t.cancelEdit}</button>
                <button class="danger" type="button" onclick={remove} disabled={saving || deleting}>{deleting ? t.deleting : t.delete}</button>
            {/if}
        </div>

        {#if errorMessage}<p class="message error" role="alert">{errorMessage}</p>{/if}
        {#if successMessage}<p class="message success" role="status">{successMessage}</p>{/if}
    </section>
{/if}

<style>
    .label-editor-panel { padding: 14px; border: 1px solid rgba(200,163,85,.7); border-radius: 9px; background: rgba(16,16,20,.98); color: #f0f0f2; }
    .panel-heading,.library-heading,.actions,.check-row { display:flex; align-items:center; gap:8px; }
    .panel-heading,.library-heading { justify-content:space-between; }
    .panel-heading { margin-bottom:10px; }
    .panel-heading>div { display:grid; gap:2px; }
    .eyebrow { color:#c8a355; font-size:.66rem; font-weight:800; text-transform:uppercase; letter-spacing:.08em; }
    .panel-heading strong { font-size:.95rem; }
    .library { display:grid; gap:8px; margin-bottom:10px; padding:9px; border:1px solid #2c2c34; border-radius:7px; background:rgba(10,10,13,.72); }
    .library-heading strong { font-size:.74rem; }
    .help { margin:8px 0 10px; color:#9797a1; font-size:.72rem; line-height:1.4; }
    label { display:grid; gap:5px; margin-bottom:9px; }
    label>span { color:#b8b8c0; font-size:.69rem; font-weight:700; }
    input,select { width:100%; box-sizing:border-box; padding:8px 9px; border:1px solid #34343e; border-radius:5px; outline:none; background:#0b0b0e; color:#f4f4f5; font:inherit; font-size:.78rem; }
    input:focus,select:focus { border-color:#c8a355; box-shadow:0 0 0 2px rgba(200,163,85,.12); }
    input[type='color'] { min-height:38px; padding:4px; }
    .grid { display:grid; gap:8px; }
    .two { grid-template-columns:minmax(0,1fr) minmax(0,1fr); }
    .advanced { margin:4px 0 10px; border:1px solid #303039; border-radius:6px; background:#111116; }
    .advanced summary { cursor:pointer; padding:9px; color:#d8b86f; font-size:.72rem; font-weight:800; }
    .advanced-body { padding:0 9px 9px; }
    .check-row { margin:0; display:flex; }
    .check-row input { width:auto; accent-color:#c8a355; }
    .position-toolbar { display:flex; align-items:center; flex-wrap:wrap; gap:7px; margin:-1px 0 8px; }
    .position-button { padding:7px 10px; border:1px solid #66593b; border-radius:5px; background:#17171c; color:#d8b86f; font-size:.69rem; font-weight:800; cursor:pointer; }
    .position-button.active { border-color:#d8b86f; background:rgba(200,163,85,.14); box-shadow:0 0 0 2px rgba(200,163,85,.09); }
    .original-location-toggle { display:flex; align-items:center; gap:6px; margin:0; padding:6px 8px; border:1px solid #2c2c34; border-radius:5px; background:rgba(10,10,13,.52); cursor:pointer; }
    .original-location-toggle input { width:auto; margin:0; accent-color:#c8a355; }
    .original-location-toggle span { color:#f0f0f2; font-size:.68rem; font-weight:800; }
    .position-help { display:block; margin:-4px 0 9px; color:#91919b; font-size:.63rem; line-height:1.35; }
    .actions { align-items:stretch; flex-wrap:wrap; margin-top:10px; }
    button { cursor:pointer; }
    button:disabled { opacity:.48; cursor:not-allowed; }
    .primary,.secondary,.danger,.small-button { border-radius:5px; font-weight:800; }
    .primary { flex:1; padding:9px 12px; border:1px solid #c8a355; background:#c8a355; color:#111116; }
    .secondary { flex:1; padding:9px 12px; border:1px solid #6d5d39; background:#17171c; color:#d8b86f; }
    .danger { padding:9px 12px; border:1px solid #8e4e4e; background:transparent; color:#e0a0a0; }
    .small-button { padding:7px 9px; border:1px solid #544a35; background:#17171c; color:#d6b96e; font-size:.68rem; }
    .message { margin:9px 0 0; padding:8px 9px; border-radius:5px; font-size:.72rem; line-height:1.4; }
    .error { border:1px solid rgba(192,88,88,.5); background:rgba(120,35,35,.18); color:#efb2b2; }
    .success { border:1px solid rgba(87,162,106,.45); background:rgba(46,110,61,.17); color:#afe0b9; }
    @media (max-width:640px) { .two { grid-template-columns:1fr; } .actions { flex-direction:column; } }

    .coordinate-control-x { display:grid; grid-template-columns:34px minmax(0,1fr) 34px; align-items:stretch; border:1px solid #34343e; border-radius:5px; background:#0b0b0e; overflow:hidden; }
    .coordinate-control-x input { min-width:0; border:0; border-radius:0; box-shadow:none !important; text-align:center; -moz-appearance:textfield; }
    .coordinate-control-x input::-webkit-outer-spin-button, .coordinate-control-x input::-webkit-inner-spin-button { -webkit-appearance:none; margin:0; }
    .coordinate-control-x button { border:0; background:#17171c; color:#d8b86f; font-weight:800; }
    .coordinate-control-x button:first-child { border-right:1px solid #34343e; }
    .coordinate-control-x button:last-child { border-left:1px solid #34343e; }
</style>
