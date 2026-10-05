<script>
    import { MARKER_CONTENT_TYPES, contentTypeLabel } from '$lib/editor/marker-content.js';

    let {
        language = 'en',
        value = $bindable([]),
        disabled = false,
        showPortuguese = true
    } = $props();

    const TEXT = {
        en: {
            title: 'Additional content',
            optional: 'optional',
            add: 'Add content',
            remove: 'Remove',
            textEn: 'Text — EN',
            textPt: 'Text — PT',
            empty: 'Add NPCs, items, rewards, requirements or notes only when this marker needs them.'
        },
        pt: {
            title: 'Conteúdo adicional',
            optional: 'opcional',
            add: 'Adicionar conteúdo',
            remove: 'Remover',
            textEn: 'Texto — EN',
            textPt: 'Texto — PT',
            empty: 'Adiciona NPCs, itens, recompensas, requisitos ou notas apenas quando este marcador precisar.'
        }
    };

    let t = $derived(TEXT[language] ?? TEXT.en);
    let menuOpen = $state(false);

    function addItem(type) {
        value = [
            ...(Array.isArray(value) ? value : []),
            { type, textEn: '', textPt: '' }
        ];
        menuOpen = false;
    }

    function setItem(index, field, nextValue) {
        value = value.map((item, itemIndex) =>
            itemIndex === index ? { ...item, [field]: nextValue } : item
        );
    }

    function removeItem(index) {
        value = value.filter((_, itemIndex) => itemIndex !== index);
    }
</script>

<section class="content-editor">
    <header class="content-heading">
        <div>
            <strong>{t.title}</strong>
            <small>({t.optional})</small>
        </div>
        <div class="add-wrap">
            <button class="add-button" type="button" onclick={() => menuOpen = !menuOpen} {disabled}>
                ＋ {t.add}
            </button>
            {#if menuOpen}
                <div class="add-menu">
                    {#each MARKER_CONTENT_TYPES as type}
                        <button type="button" onclick={() => addItem(type.id)} {disabled}>
                            {contentTypeLabel(type.id, language)}
                        </button>
                    {/each}
                </div>
            {/if}
        </div>
    </header>

    {#if !value?.length}
        <p class="empty-help">{t.empty}</p>
    {:else}
        <div class="content-list">
            {#each value as item, index}
                <article class="content-card">
                    <div class="card-heading">
                        <span>{contentTypeLabel(item.type, language)}</span>
                        <button class="remove-button" type="button" onclick={() => removeItem(index)} {disabled}>{t.remove}</button>
                    </div>
                    <label>
                        <span>{t.textEn}</span>
                        <input
                            value={item.textEn ?? ''}
                            oninput={(event) => setItem(index, 'textEn', event.currentTarget.value)}
                            {disabled}
                        />
                    </label>
                    {#if showPortuguese}
                        <label>
                            <span>{t.textPt} ({t.optional})</span>
                            <input
                                value={item.textPt ?? ''}
                                oninput={(event) => setItem(index, 'textPt', event.currentTarget.value)}
                                {disabled}
                            />
                        </label>
                    {/if}
                </article>
            {/each}
        </div>
    {/if}
</section>

<style>
    .content-editor{display:grid;gap:9px;margin:10px 0;padding:10px;border:1px solid #303039;border-radius:8px;background:#101014}
    .content-heading,.card-heading{display:flex;align-items:center;justify-content:space-between;gap:8px}.content-heading>div:first-child{display:flex;align-items:baseline;gap:5px}.content-heading strong{color:#d8b86f;font-size:.73rem}.content-heading small,.empty-help{color:#85858f;font-size:.66rem}.empty-help{margin:0;line-height:1.4}.add-wrap{position:relative}.add-button,.add-menu button,.remove-button{border:1px solid #3a3a45;border-radius:6px;background:#17171c;color:#ddd;cursor:pointer;font:inherit}.add-button{padding:7px 9px;color:#d8b86f;font-size:.68rem;font-weight:800}.add-menu{position:absolute;right:0;top:calc(100% + 5px);z-index:20;min-width:150px;display:grid;gap:3px;padding:5px;border:1px solid #3a3a45;border-radius:7px;background:#111116;box-shadow:0 12px 26px rgba(0,0,0,.45)}.add-menu button{padding:7px 8px;text-align:left;font-size:.68rem}.add-menu button:hover:not(:disabled){border-color:#c8a355;color:#f1d58e}.content-list{display:grid;gap:8px}.content-card{display:grid;gap:7px;padding:9px;border:1px solid #2f2f38;border-radius:7px;background:#0b0b0e}.card-heading span{color:#eee;font-size:.72rem;font-weight:800}.remove-button{padding:5px 7px;color:#efb2b2;font-size:.62rem}label{display:grid;gap:4px}label>span{color:#aaaab3;font-size:.65rem;font-weight:700}input{width:100%;box-sizing:border-box;padding:8px 9px;border:1px solid #34343e;border-radius:6px;outline:none;background:#0f0f13;color:#eee;font:inherit;font-size:.73rem}input:focus{border-color:#c8a355;box-shadow:0 0 0 2px rgba(200,163,85,.11)}button:disabled,input:disabled{opacity:.5;cursor:not-allowed}
</style>
