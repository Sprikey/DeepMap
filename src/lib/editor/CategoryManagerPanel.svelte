<script>
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';
    import {
        createEditorCategory,
        deleteEditorCategory,
        loadEditorCategories,
        slugifyCategoryId,
        updateEditorCategory
    } from '$lib/editor/category-editor.js';

    let {
        gameId,
        language = 'en',
        categories = {},
        categoryGroups = [],
        standalone = false,
        onChanged = async () => {}
    } = $props();

    const TEXT = {
        en: {
            title: 'Categories & icons',
            manage: 'Manage categories',
            newCategory: 'New category',
            chooseCategory: 'Choose a category…',
            categoryId: 'Category ID',
            idHelp: 'Generated automatically from the English name.',
            group: 'Group',
            nameEn: 'Name — EN',
            namePt: 'Name — PT',
            iconSource: 'Icon source',
            noIcon: 'No icon',
            staticIcon: 'Static file',
            externalIcon: 'External URL',
            iconRef: 'Icon path / URL',
            iconRefHelp: 'Example: /games/elden-ring/icons/boss.svg',
            iconPreview: 'Live marker preview',
            color: 'Marker colour',
            advanced: 'Marker appearance',
            size: 'Size',
            symbolSize: 'Symbol size',
            sortOrder: 'Order',
            sortOrderHelp: 'Controls the category position. Lower numbers appear first. New categories get this automatically.',
            active: 'Active',
            activeHelp: 'Active categories appear in the map/filter menus. Inactive categories stay saved but are hidden.',
            advancedCategory: 'Advanced category options',
            inactive: 'inactive',
            save: 'Save category',
            saving: 'Saving…',
            saved: 'Category saved.',
            delete: 'Delete category',
            deleting: 'Deleting…',
            deleted: 'Category deleted.',
            confirmDelete: 'Delete this category? This cannot be undone.',
            categoryInUse: 'This category cannot be deleted because markers still use it. Move or delete those markers first.',
            deleteError: 'Could not delete the category.',
            required: 'Fill the English and Portuguese names and choose a group.',
            invalidId: 'The category ID must use lowercase letters, numbers, underscores or hyphens.',
            invalidIcon: 'Add an icon path/URL or choose No icon.',
            invalidColor: 'Use a colour in #RRGGBB format.',
            duplicate: 'A category with this ID already exists.',
            saveError: 'Could not save the category.',
            r2Later: 'R2 upload will be added in the upload phase. For now use a static file path or external URL.'
        },
        pt: {
            title: 'Categorias e ícones',
            manage: 'Gerir categorias',
            newCategory: 'Nova categoria',
            chooseCategory: 'Escolhe uma categoria…',
            categoryId: 'ID da categoria',
            idHelp: 'Gerado automaticamente a partir do nome em inglês.',
            group: 'Grupo',
            nameEn: 'Nome — EN',
            namePt: 'Nome — PT',
            iconSource: 'Origem do ícone',
            noIcon: 'Sem ícone',
            staticIcon: 'Ficheiro estático',
            externalIcon: 'URL externo',
            iconRef: 'Caminho / URL do ícone',
            iconRefHelp: 'Exemplo: /games/elden-ring/icons/boss.svg',
            iconPreview: 'Pré-visualização do marcador',
            color: 'Cor do marcador',
            advanced: 'Aspeto do marcador',
            size: 'Tamanho',
            symbolSize: 'Tamanho do símbolo',
            sortOrder: 'Ordem',
            sortOrderHelp: 'Controla a posição da categoria. Números mais baixos aparecem primeiro. Nas novas categorias é automático.',
            active: 'Ativa',
            activeHelp: 'Categorias ativas aparecem no mapa/filtros. Inativas ficam guardadas, mas escondidas.',
            advancedCategory: 'Opções avançadas da categoria',
            inactive: 'inativa',
            save: 'Guardar categoria',
            saving: 'A guardar…',
            saved: 'Categoria guardada.',
            delete: 'Eliminar categoria',
            deleting: 'A eliminar…',
            deleted: 'Categoria eliminada.',
            confirmDelete: 'Eliminar esta categoria? Esta ação não pode ser anulada.',
            categoryInUse: 'Não podes eliminar esta categoria porque ainda existem marcadores a usá-la. Move ou elimina esses marcadores primeiro.',
            deleteError: 'Não foi possível eliminar a categoria.',
            required: 'Preenche os nomes EN e PT e escolhe um grupo.',
            invalidId: 'O ID da categoria só pode usar letras minúsculas, números, _ ou -.',
            invalidIcon: 'Adiciona o caminho/URL do ícone ou escolhe Sem ícone.',
            invalidColor: 'Usa uma cor no formato #RRGGBB.',
            duplicate: 'Já existe uma categoria com este ID.',
            saveError: 'Não foi possível guardar a categoria.',
            r2Later: 'O upload para R2 será adicionado na fase de uploads. Para já usa um ficheiro estático ou URL externo.'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let expanded = $state(false);
    let saving = $state(false);
    let deleting = $state(false);
    let loadingCategories = $state(false);
    let loadedCategoriesOnce = false;
    let adminCategories = $state([]);
    let errorMessage = $state('');
    let successMessage = $state('');
    let editingId = $state(null);
    let activeGroupId = $state('');

    let categoryId = $state('');
    let groupId = $state('');
    let nameEn = $state('');
    let namePt = $state('');
    let iconSource = $state('none');
    let iconRef = $state('');
    const DEFAULT_PREVIEW_COLOR = '#2f8fff';
    let color = $state(DEFAULT_PREVIEW_COLOR);
    let markerSize = $state('30');
    let symbolSize = $state('18');
    let sortOrder = $state('');
    let isActive = $state(true);

    let sortedCategories = $derived(
        (adminCategories.length ? adminCategories : Object.values(categories)).slice().sort(
            (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
        )
    );

    let sortedGroups = $derived(
        [...categoryGroups].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
    );

    let visibleCategories = $derived(
        sortedCategories.filter((category) => !activeGroupId || category.group === activeGroupId)
    );

    let previewWidth = $derived(Number(markerSize) > 0 ? Number(markerSize) : 30);
    let previewHeight = $derived(Math.max(1, Math.round(previewWidth * 1.3)));
    let previewSymbolSize = $derived(Number(symbolSize) > 0 ? Number(symbolSize) : 18);
    let previewSvgSymbolSize = $derived((previewSymbolSize / previewWidth) * 40);
    let previewSvgSymbolX = $derived((40 - previewSvgSymbolSize) / 2);

    function localisedLabel(item) {
        return item?.label?.[language] ?? item?.label?.en ?? item?.label?.pt ?? item?.id ?? '';
    }

    function clearMessages() {
        errorMessage = '';
        successMessage = '';
    }

    function nextSortOrder() {
        const highest = sortedCategories.reduce(
            (max, category) => Math.max(max, Number(category.sortOrder ?? 0)),
            0
        );
        return highest + 10;
    }

    function resetForm() {
        editingId = null;
        categoryId = '';
        groupId = activeGroupId || sortedGroups[0]?.id || '';
        nameEn = '';
        namePt = '';
        iconSource = 'none';
        iconRef = '';
        color = DEFAULT_PREVIEW_COLOR;
        markerSize = '30';
        symbolSize = '18';
        sortOrder = String(nextSortOrder());
        isActive = true;
        clearMessages();
    }

    function loadCategory(category) {
        if (!category) return;
        editingId = category.id;
        categoryId = category.id;
        groupId = category.group ?? '';
        activeGroupId = category.group ?? activeGroupId;
        nameEn = category.label?.en ?? '';
        namePt = category.label?.pt ?? '';
        iconSource = category.iconSource ?? (category.icon ? 'static' : 'none');
        iconRef = category.iconRef ?? category.icon ?? '';
        color = category.color ?? DEFAULT_PREVIEW_COLOR;
        markerSize = String(category.markerWidth ?? (category.markerHeight ? Math.round(Number(category.markerHeight) / 1.3) : 30));
        symbolSize = String(category.symbolSize ?? 18);
        sortOrder = String(category.sortOrder ?? 0);
        isActive = category.isActive !== false;
        clearMessages();
    }

    async function refreshCategories() {
        loadingCategories = true;
        try {
            adminCategories = await loadEditorCategories({
                supabase: getSupabaseBrowserClient(),
                gameId
            });
        } catch (error) {
            console.error('DeepMap category editor load:', error);
        } finally {
            loadingCategories = false;
        }
    }

    function chooseCategory(event) {
        const id = event.currentTarget.value;
        if (!id) {
            resetForm();
            return;
        }
        const category = sortedCategories.find((item) => item.id === id) ?? categories[id];
        if (category) loadCategory(category);
    }

    function selectGroup(groupIdValue) {
        activeGroupId = groupIdValue;
        if (editingId === null) {
            groupId = groupIdValue;
            categoryId = '';
            nameEn = '';
            namePt = '';
            iconSource = 'none';
            iconRef = '';
            color = DEFAULT_PREVIEW_COLOR;
            markerSize = '30';
            symbolSize = '18';
            sortOrder = String(nextSortOrder());
            isActive = true;
            clearMessages();
        } else if (groupId !== groupIdValue) {
            editingId = null;
            resetForm();
        }
    }

    function maybeCreateId() {
        if (editingId !== null) return;
        categoryId = slugifyCategoryId(nameEn);
    }

    function validate() {
        if (!nameEn.trim() || !namePt.trim() || !groupId) return t.required;
        if (!/^[a-z0-9]+(?:[_-][a-z0-9]+)*$/.test(categoryId)) return t.invalidId;
        if (iconSource !== 'none' && !iconRef.trim()) return t.invalidIcon;
        if (!/^#[0-9A-Fa-f]{6}$/.test(color)) return t.invalidColor;
        return '';
    }

    async function saveCategory() {
        if (saving) return;
        clearMessages();
        maybeCreateId();

        const validationError = validate();
        if (validationError) {
            errorMessage = validationError;
            return;
        }

        saving = true;
        try {
            const category = {
                id: categoryId,
                groupId,
                nameEn,
                namePt,
                iconSource,
                iconRef,
                color,
                markerWidth: markerSize,
                markerHeight: markerSize ? Math.max(1, Math.round(Number(markerSize) * 1.3)) : '',
                symbolSize,
                sortOrder,
                isActive
            };

            if (editingId === null) {
                await createEditorCategory({
                    supabase: getSupabaseBrowserClient(),
                    gameId,
                    category
                });
            } else {
                await updateEditorCategory({
                    supabase: getSupabaseBrowserClient(),
                    gameId,
                    categoryId: editingId,
                    category
                });
            }

            successMessage = t.saved;
            editingId = categoryId;
            await refreshCategories();
            await onChanged({ action: 'category-save', categoryId });
        } catch (error) {
            console.error('DeepMap category editor save:', error);
            errorMessage = error?.code === '23505' ? t.duplicate : t.saveError;
        } finally {
            saving = false;
        }
    }

    async function removeCategory() {
        if (editingId === null || saving || deleting) return;
        if (!window.confirm(t.confirmDelete)) return;

        deleting = true;
        clearMessages();

        try {
            const deletedId = editingId;
            await deleteEditorCategory({
                supabase: getSupabaseBrowserClient(),
                gameId,
                categoryId: deletedId
            });

            resetForm();
            await refreshCategories();
            successMessage = t.deleted;
            await onChanged({ action: 'category-delete', categoryId: deletedId });
        } catch (error) {
            console.error('DeepMap category editor delete:', error);
            errorMessage = error?.code === 'CATEGORY_IN_USE' || error?.code === '23503'
                ? t.categoryInUse
                : t.deleteError;
        } finally {
            deleting = false;
        }
    }

    $effect(() => {
        if (standalone) expanded = true;
    });

    $effect(() => {
        if (!expanded || loadedCategoriesOnce) return;
        loadedCategoriesOnce = true;
        void refreshCategories();
    });

    $effect(() => {
        if (!expanded || !sortedGroups.length) return;
        if (!activeGroupId) activeGroupId = sortedGroups[0]?.id ?? '';
        if (editingId !== null || groupId) return;
        groupId = activeGroupId || sortedGroups[0]?.id || '';
        sortOrder = String(nextSortOrder());
    });

</script>

<div class:standalone class="category-manager">
    {#if !standalone}
        <button
            class="category-toggle"
            type="button"
            onclick={() => {
                expanded = !expanded;
                if (expanded && editingId === null && !groupId) resetForm();
            }}
        >
            <span>＋ {t.manage}</span>
            <span aria-hidden="true">{expanded ? '▴' : '▾'}</span>
        </button>
    {/if}

    {#if expanded}
        <div class="category-body">
            <div class="category-heading">
                <div>
                    <span class="eyebrow">{t.title}</span>
                    <strong>{editingId === null ? t.newCategory : localisedLabel(sortedCategories.find((item) => item.id === editingId))}</strong>
                </div>
                <button class="small-button" type="button" onclick={resetForm} disabled={saving || deleting}>
                    {t.newCategory}
                </button>
            </div>

            <div class="group-tabs" role="tablist" aria-label={t.group}>
                {#each sortedGroups as group}
                    <button
                        type="button"
                        class:active={activeGroupId === group.id}
                        onclick={() => selectGroup(group.id)}
                        disabled={saving || deleting}
                    >{localisedLabel(group)}</button>
                {/each}
            </div>

            <select onchange={chooseCategory} value={editingId ?? ''} disabled={saving || deleting || loadingCategories}>
                <option value="">{t.chooseCategory}</option>
                {#each visibleCategories as category}
                    <option value={category.id}>
                        {localisedLabel(category)} — {category.id}{category.isActive === false ? ` (${t.inactive})` : ''}
                    </option>
                {/each}
            </select>

            <aside class="live-marker-preview">
                <span>{t.iconPreview}</span>
                <div class="preview-stage">
                    <svg
                        width={previewWidth}
                        height={previewHeight}
                        viewBox="0 0 40 52"
                        preserveAspectRatio="xMidYMid meet"
                        xmlns="http://www.w3.org/2000/svg"
                        aria-label={t.iconPreview}
                    >
                        <path d="M20 1 C9.5 1 1 9.5 1 20 C1 34 20 51 20 51 C20 51 39 34 39 20 C39 9.5 30.5 1 20 1 Z" fill={color} opacity="0.82" />
                        {#if iconSource !== 'none' && iconRef}
                            <image
                                href={iconRef}
                                x={previewSvgSymbolX}
                                y="8"
                                width={previewSvgSymbolSize}
                                height={previewSvgSymbolSize}
                                preserveAspectRatio="xMidYMid meet"
                            />
                        {/if}
                    </svg>
                </div>
            </aside>

            <div class="two-columns">
                <label>
                    <span>{t.nameEn}</span>
                    <input bind:value={nameEn} oninput={maybeCreateId} disabled={saving || deleting} />
                </label>
                <label>
                    <span>{t.namePt}</span>
                    <input bind:value={namePt} disabled={saving || deleting} />
                </label>
            </div>

            <div class="two-columns">
                <label>
                    <span>{t.categoryId}</span>
                    <input bind:value={categoryId} readonly disabled={saving || deleting} />
                    {#if editingId === null}<small>{t.idHelp}</small>{/if}
                </label>
                <label>
                    <span>{t.group}</span>
                    <select bind:value={groupId} onchange={() => activeGroupId = groupId} disabled={saving || deleting}>
                        {#each sortedGroups as group}
                            <option value={group.id}>{localisedLabel(group)}</option>
                        {/each}
                    </select>
                </label>
            </div>

            <div class="two-columns">
                <label>
                    <span>{t.iconSource}</span>
                    <select bind:value={iconSource} disabled={saving || deleting}>
                        <option value="none">{t.noIcon}</option>
                        <option value="static">{t.staticIcon}</option>
                        <option value="external">{t.externalIcon}</option>
                    </select>
                </label>
                <label>
                    <span>{t.color}</span>
                    <input type="color" bind:value={color} disabled={saving || deleting} />
                </label>
            </div>

            {#if iconSource !== 'none'}
                <label>
                    <span>{t.iconRef}</span>
                    <input bind:value={iconRef} placeholder="/games/elden-ring/icons/boss.svg" disabled={saving || deleting} />
                    <small>{t.iconRefHelp}</small>
                </label>
            {/if}

            <details class="advanced-options">
                <summary>{t.advanced}</summary>
                <div class="two-columns">
                    <label>
                        <span>{t.size}</span>
                        <input type="number" min="8" max="96" step="1" bind:value={markerSize} disabled={saving || deleting} />
                    </label>
                    <label>
                        <span>{t.symbolSize}</span>
                        <input type="number" min="1" step="1" bind:value={symbolSize} disabled={saving || deleting} />
                    </label>
                </div>
            </details>

            <details class="advanced-options">
                <summary>{t.advancedCategory}</summary>
                <div class="two-columns compact-row">
                    <label>
                        <span>{t.sortOrder}</span>
                        <input type="number" step="10" bind:value={sortOrder} disabled={saving || deleting} />
                        <small>{t.sortOrderHelp}</small>
                    </label>
                    <label class="active-option">
                        <span class="active-row">
                            <input type="checkbox" bind:checked={isActive} disabled={saving || deleting} />
                            <span>{t.active}</span>
                        </span>
                        <small>{t.activeHelp}</small>
                    </label>
                </div>
            </details>

            <div class="category-actions">
                <button class="primary-button" type="button" onclick={saveCategory} disabled={saving || deleting}>
                    {saving ? t.saving : t.save}
                </button>

                {#if editingId !== null}
                    <button class="danger-button" type="button" onclick={removeCategory} disabled={saving || deleting}>
                        {deleting ? t.deleting : t.delete}
                    </button>
                {/if}
            </div>

            <p class="r2-note">{t.r2Later}</p>

            {#if errorMessage}<p class="message error" role="alert">{errorMessage}</p>{/if}
            {#if successMessage}<p class="message success" role="status">{successMessage}</p>{/if}
        </div>
    {/if}
</div>

<style>
    .category-manager { margin-bottom:12px; border:1px solid rgba(200,163,85,.34); border-radius:7px; background:rgba(11,11,14,.72); overflow:hidden; }
    .category-manager.standalone { margin:0; border-color:rgba(200,163,85,.7); border-radius:9px; background:rgba(16,16,20,.98); }
    .category-toggle { width:100%; display:flex; align-items:center; justify-content:space-between; gap:10px; padding:9px 10px; border:0; background:rgba(200,163,85,.07); color:#d8b86f; font-weight:800; cursor:pointer; }
    .category-body { display:grid; gap:9px; padding:12px; position:relative; }
    .category-manager:not(.standalone) .category-body { border-top:1px solid rgba(200,163,85,.22); }
    .category-heading { display:flex; align-items:center; justify-content:space-between; gap:10px; }
    .category-heading>div { display:grid; gap:2px; }
    .category-heading strong { color:#f2f2f4; font-size:.86rem; }
    .group-tabs { display:grid; grid-template-columns:repeat(auto-fit,minmax(110px,1fr)); gap:6px; }
    .group-tabs button { padding:8px 10px; border:1px solid #3a3a45; border-radius:6px; background:#17171c; color:#bcbcc4; font:inherit; font-size:.7rem; font-weight:800; cursor:pointer; }
    .group-tabs button.active { border-color:#c8a355; background:#211d14; color:#f1d58e; box-shadow:0 0 0 2px rgba(200,163,85,.08); }
    .eyebrow { color:#c8a355; font-size:.66rem; font-weight:800; text-transform:uppercase; letter-spacing:.08em; }
    label { display:grid; gap:5px; }
    label>span,.live-marker-preview>span { color:#b8b8c0; font-size:.69rem; font-weight:700; }
    small { color:#777781; font-size:.63rem; line-height:1.35; }
    input,select { width:100%; box-sizing:border-box; padding:8px 9px; border:1px solid #34343e; border-radius:5px; outline:none; background:#0b0b0e; color:#f4f4f5; font:inherit; font-size:.76rem; }
    input:focus,select:focus { border-color:#c8a355; box-shadow:0 0 0 2px rgba(200,163,85,.12); }
    input[type='color'] { min-height:35px; padding:3px; }
    .two-columns { display:grid; gap:8px; grid-template-columns:minmax(0,1fr) minmax(0,1fr); }
    .live-marker-preview { position:fixed; top:calc(var(--deepmap-site-header-height,72px) + var(--deepmap-game-subheader-height,54px) + 104px); right:462px; z-index:999998; width:150px; display:grid; gap:7px; padding:10px; box-sizing:border-box; border:1px solid rgba(200,163,85,.55); border-radius:9px; background:rgba(11,11,14,.98); box-shadow:0 12px 30px rgba(0,0,0,.45); pointer-events:auto; }
    .preview-stage { min-height:112px; display:grid; place-items:center; border:1px solid #303039; border-radius:7px; background:#0b0b0e; overflow:hidden; }
    .preview-stage svg { display:block; overflow:visible; }
    .advanced-options { border:1px solid #2c2c34; border-radius:6px; padding:8px; background:#101014; }
    .advanced-options summary { color:#aaaab3; font-size:.7rem; font-weight:700; cursor:pointer; }
    .advanced-options[open] summary { margin-bottom:8px; }
    .active-row { display:flex; align-items:center; align-self:end; min-height:35px; padding:0 9px; border:1px solid #303039; border-radius:5px; background:#111116; }
    .active-row input { width:auto; accent-color:#c8a355; }
    .active-option { align-content:start; }
    .category-actions { display:flex; align-items:center; gap:8px; }
    .primary-button,.small-button,.danger-button { border-radius:5px; font-weight:800; cursor:pointer; }
    .primary-button { padding:9px 12px; border:1px solid #c8a355; background:#c8a355; color:#111116; }
    .small-button { padding:6px 8px; border:1px solid #544a35; background:#17171c; color:#d6b96e; font-size:.66rem; }
    .danger-button { padding:9px 12px; border:1px solid #8e4e4e; background:#241516; color:#efb2b2; }
    button:disabled,input:disabled,select:disabled { opacity:.5; cursor:not-allowed; }
    .r2-note { margin:0; color:#7f7f89; font-size:.66rem; line-height:1.4; }
    .message { margin:0; padding:8px 9px; border-radius:5px; font-size:.7rem; line-height:1.4; }
    .message.error { border:1px solid rgba(192,88,88,.5); background:rgba(120,35,35,.18); color:#efb2b2; }
    .message.success { border:1px solid rgba(87,162,106,.45); background:rgba(46,110,61,.17); color:#afe0b9; }
    @media (max-width:900px) { .live-marker-preview { position:static; width:auto; margin:0; } }
    @media (max-width:560px) { .two-columns { grid-template-columns:1fr; } }
</style>
