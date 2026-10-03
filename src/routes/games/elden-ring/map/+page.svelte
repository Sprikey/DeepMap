
<script>
    import { onMount } from 'svelte';
    import { getSiteLanguage, subscribeSiteLanguage } from '$lib/i18n/site.js';
    import { getSupabaseBrowserClient } from '$lib/supabase/client.js';

    import { translations } from '$lib/games/elden-ring/translations.js';

    import {
        categories as fallbackCategories,
        categoryGroups as fallbackCategoryGroups,
        defaultCategoryVisibility as fallbackCategoryVisibility
    } from '$lib/games/elden-ring/categories.js';

    import { locations as fallbackLocations } from '$lib/games/elden-ring/locations.js';
    import { mapDefinitions as fallbackMapDefinitions } from '$lib/games/elden-ring/maps.js';
    import { loadDeepMapGameData } from '$lib/map/map-data.js';
    import { getVideoEmbedUrl, normaliseHttpUrl } from '$lib/map/media.js';
    import MarkerEditorPanel from '$lib/editor/MarkerEditorPanel.svelte';
    import CategoryManagerPanel from '$lib/editor/CategoryManagerPanel.svelte';
    import MapLabelEditorPanel from '$lib/editor/MapLabelEditorPanel.svelte';
    import ModerationPanel from '$lib/editor/ModerationPanel.svelte';
    import CommunityMarkerPanel from '$lib/community/CommunityMarkerPanel.svelte';

    const GAME_ID = 'elden-ring';
    const PREVIEW_MARKER_COLOR = '#2f8fff';
    const PREVIEW_MARKER_OPACITY = 0.82;

    // Estado normalizado consumido pelo mapa. Começa com os ficheiros legacy
    // para nunca deixar o mapa vazio durante a migração para Supabase.
    let categories = $state({ ...fallbackCategories });
    let categoryGroups = $state([...fallbackCategoryGroups]);
    let locations = $state([...fallbackLocations]);
    let mapLabels = $state([]);
    let mapDefinitions = $state({ ...fallbackMapDefinitions });

    let mapContainer;
    let map;
    let Leaflet;
    let mapImageOverlay = null;

    // O Editor 2.0 é privado. Esta flag serve apenas para decidir se a UI
    // aparece; as permissões reais de escrita continuam protegidas por RLS.
    let isEditorAdmin = $state(false);
    let editorAccessChecked = $state(false);
    let currentMapUser = $state(null);

    async function loadEditorAccess() {
        try {
            const supabase = getSupabaseBrowserClient();
            const { data: userData, error: userError } = await supabase.auth.getUser();

            currentMapUser = userError ? null : userData.user;

            if (userError || !userData.user) {
                isEditorAdmin = false;
                return;
            }

            const { data, error } = await supabase.rpc('is_deepmap_admin');

            if (error) {
                console.warn('DeepMap editor access check:', error.message);
                isEditorAdmin = false;
                return;
            }

            isEditorAdmin = data === true;
        } catch (error) {
            console.warn('DeepMap editor access check:', error);
            isEditorAdmin = false;
        } finally {
            editorAccessChecked = true;
            if (map && Leaflet) renderLocationMarkers();
        }
    }


    /* ==========================================
       IDIOMAS / TRADUÇÕES — SVELTE 5
       ========================================== */

    let currentLanguage = $state('en');

    let currentTexts = $derived(
        translations[currentLanguage] ?? translations.en
    );

    function t(key) {
        return (
            translations[currentLanguage]?.[key] ??
            translations.en?.[key] ??
            key
        );
    }

    $effect(() => {
        const unsubscribe = subscribeSiteLanguage((language) => {
            if (currentLanguage === language) return;

            currentLanguage = language;
            renderLocationMarkers();
            renderMapLabels();
        });

        return unsubscribe;
    });


    /* ==========================================
       FILTROS — v1.0.28
       ========================================== */

    let categoryVisibility = $state({
        ...fallbackCategoryVisibility
    });

    // Os mesmos dados alimentam os filtros desktop e mobile e reagem quando
    // as categorias passam dos ficheiros legacy para o Supabase.
    let filterGroups = $derived(
        categoryGroups.map((group) => ({
            ...group,
            categories: Object.values(categories)
                .filter((category) => category.group === group.id)
                .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
        }))
    );

    function syncCategoryVisibility() {
        const nextVisibility = {};

        for (const categoryId of Object.keys(categories)) {
            nextVisibility[categoryId] = categoryVisibility[categoryId] !== false;
        }

        categoryVisibility = nextVisibility;
    }

    function getLocalisedValue(values, fallbackKey = null) {
        if (values && typeof values === 'object') {
            return values[currentLanguage] ?? values.en ?? values.pt ?? '';
        }

        if (fallbackKey) return t(fallbackKey);

        return typeof values === 'string' ? values : '';
    }

    function getGroupLabel(group) {
        return getLocalisedValue(group.label, group.labelKey);
    }

    function getCategoryLabel(category) {
        return getLocalisedValue(category.label, category.labelKey);
    }

    function getLocationTitle(location) {
        return getLocalisedValue(location.title, location.nameKey);
    }

    function getLocationDescription(location) {
        return getLocalisedValue(location.description, location.descriptionKey);
    }


    function getMapLabelText(label) {
        return getLocalisedValue(label.text);
    }

    async function loadGameMapData() {
        const supabase = getSupabaseBrowserClient();
        const data = await loadDeepMapGameData({
            supabase,
            gameId: GAME_ID,
            fallback: {
                mapDefinitions: { ...fallbackMapDefinitions },
                categoryGroups: [...fallbackCategoryGroups],
                categories: { ...fallbackCategories },
                locations: [...fallbackLocations],
                mapLabels: []
            }
        });

        mapDefinitions = data.mapDefinitions;
        categoryGroups = data.categoryGroups;
        categories = data.categories;
        locations = data.locations;
        mapLabels = data.mapLabels ?? [];
        syncCategoryVisibility();

        console.info('DeepMap map data sources:', data.sources);
    }

    function setCategoryVisibility(categoryId, visible) {
        categoryVisibility[categoryId] = visible;
        renderLocationMarkers();
    }

    function toggleCategory(categoryId) {
        setCategoryVisibility(
            categoryId,
            categoryVisibility[categoryId] === false
        );
    }

    function setAllCategoryVisibility(visible) {
        for (const categoryId of Object.keys(categories)) {
            categoryVisibility[categoryId] = visible;
        }

        renderLocationMarkers();
    }


    /* ==========================================
       MAPAS / CAMADAS
       ========================================== */

    let activeMapLayer = 'surface';
    let markerLayerGroups = {};
    let mapLabelLayerGroups = {};

    function getMapBounds(mapDefinition) {
        return [
            [0, 0],
            [mapDefinition.height, mapDefinition.width]
        ];
    }

    function setupMarkerLayers() {
        for (const layerId of Object.keys(mapDefinitions)) {
            markerLayerGroups[layerId] = Leaflet.layerGroup();
            mapLabelLayerGroups[layerId] = Leaflet.layerGroup();
        }

        markerLayerGroups[activeMapLayer]?.addTo(map);
        mapLabelLayerGroups[activeMapLayer]?.addTo(map);
    }

    function setActiveMapLayer(layerId) {
        if (!map) return;

        const definition = mapDefinitions[layerId];
        if (!definition) return;

        for (const group of [...Object.values(markerLayerGroups), ...Object.values(mapLabelLayerGroups)]) {
            if (map.hasLayer(group)) {
                map.removeLayer(group);
            }
        }

        activeMapLayer = layerId;

        markerLayerGroups[activeMapLayer]?.addTo(map);
        mapLabelLayerGroups[activeMapLayer]?.addTo(map);

        if (definition.image) {
            const bounds = getMapBounds(definition);

            if (mapImageOverlay) {
                map.removeLayer(mapImageOverlay);
            }

            mapImageOverlay = Leaflet.imageOverlay(
                definition.image,
                bounds
            ).addTo(map);

            mapImageOverlay.bringToBack();
            map.setMaxBounds(bounds);
            map.fitBounds(bounds);
        }
    }


    /* ==========================================
       POPUPS
       ========================================== */

    function escapeHtml(value) {
        return String(value)
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
    }

    function translateList(list) {
        if (!list || !list.length) return '';

        return list
            .map((item) => t(item))
            .join(', ');
    }

    function createPopupInfoRow(labelKey, value) {
        if (!value) return '';

        return `
            <div class="deepmap-popup-info-row">
                <span class="deepmap-popup-info-label">
                    ${escapeHtml(t(labelKey))}
                </span>

                <span class="deepmap-popup-info-value">
                    ${escapeHtml(value)}
                </span>
            </div>
        `;
    }

    function getMarkerContentTypeLabel(type) {
        const labels = {
            npc: { en: 'NPC', pt: 'NPC' },
            item: { en: 'Item', pt: 'Item' },
            reward: { en: 'Reward', pt: 'Recompensa' },
            requirement: { en: 'Requirement', pt: 'Requisito' },
            note: { en: 'Note', pt: 'Nota' }
        };
        return labels[type]?.[currentLanguage] ?? labels[type]?.en ?? type ?? '';
    }

    function buildLocationContentHtml(location) {
        const items = (location.contentItems ?? [])
            .map((item) => ({
                ...item,
                value: getLocalisedValue(item.text)
            }))
            .filter((item) => item.value);

        if (!items.length) return '';

        return `
            <div class="deepmap-popup-extra-content">
                ${items.map((item) => `
                    <div class="deepmap-popup-extra-row">
                        <span>${escapeHtml(getMarkerContentTypeLabel(item.type))}</span>
                        <strong>${escapeHtml(item.value)}</strong>
                    </div>
                `).join('')}
            </div>
        `;
    }

    function getLocationMedia(location) {
        const media = [];
        const seenImages = new Set();

        for (const image of location.images ?? []) {
            const url = image?.url ?? image?.imageRef ?? null;
            if (!url || image?.source === 'r2' || seenImages.has(url)) continue;
            seenImages.add(url);
            media.push({ type: 'image', url });
        }

        if (location.image && !seenImages.has(location.image)) {
            seenImages.add(location.image);
            media.unshift({ type: 'image', url: location.image });
        }

        const videoUrl = normaliseHttpUrl(location.videoUrl);
        if (videoUrl) {
            media.push({
                type: 'video',
                url: videoUrl,
                embedUrl: getVideoEmbedUrl(videoUrl)
            });
        }

        return media;
    }

    function buildLocationMediaHtml(location) {
        const media = getLocationMedia(location);
        if (!media.length) return '';

        const title = getLocationTitle(location);
        const videoLabel = currentLanguage === 'pt' ? 'Vídeo' : 'Video';
        const openVideoLabel = currentLanguage === 'pt' ? 'Abrir vídeo' : 'Open video';

        const slides = media.map((item, index) => {
            if (item.type === 'image') {
                return `
                    <div class="deepmap-popup-media-slide${index === 0 ? ' active' : ''}" data-media-index="${index}">
                        <img
                            src="${escapeHtml(item.url)}"
                            alt="${escapeHtml(title)}"
                            class="deepmap-popup-media-image"
                            onerror="this.closest('.deepmap-popup-media-slide').style.display='none'"
                        />
                    </div>
                `;
            }

            if (item.embedUrl) {
                return `
                    <div class="deepmap-popup-media-slide deepmap-popup-video-slide${index === 0 ? ' active' : ''}" data-media-index="${index}">
                        <iframe
                            src="${escapeHtml(item.embedUrl)}"
                            title="${escapeHtml(videoLabel)} — ${escapeHtml(title)}"
                            loading="lazy"
                            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                            allowfullscreen
                        ></iframe>
                    </div>
                `;
            }

            return `
                <div class="deepmap-popup-media-slide deepmap-popup-video-slide${index === 0 ? ' active' : ''}" data-media-index="${index}">
                    <a
                        class="deepmap-popup-video-link"
                        href="${escapeHtml(item.url)}"
                        target="_blank"
                        rel="noreferrer"
                    >▶ ${escapeHtml(openVideoLabel)}</a>
                </div>
            `;
        }).join('');

        const navigation = media.length > 1
            ? `
                <button type="button" class="deepmap-popup-media-arrow prev" data-media-prev aria-label="Previous">‹</button>
                <button type="button" class="deepmap-popup-media-arrow next" data-media-next aria-label="Next">›</button>
                <span class="deepmap-popup-media-counter" data-media-counter>1/${media.length}</span>
            `
            : '';

        return `
            <div class="deepmap-popup-media" data-media-count="${media.length}">
                ${slides}
                ${navigation}
            </div>
        `;
    }

    function buildLocationPopup(location) {
        let optionalInformation = '';

        if (location.regionKey) {
            optionalInformation += createPopupInfoRow(
                'region',
                t(location.regionKey)
            );
        }

        if (location.npcs?.length) {
            optionalInformation += createPopupInfoRow(
                'npcs',
                translateList(location.npcs)
            );
        }

        if (location.items?.length) {
            optionalInformation += createPopupInfoRow(
                'items',
                translateList(location.items)
            );
        }

        if (location.quests?.length) {
            optionalInformation += createPopupInfoRow(
                'quests',
                translateList(location.quests)
            );
        }

        if (location.notesKey) {
            optionalInformation += createPopupInfoRow(
                'notes',
                t(location.notesKey)
            );
        }

        const mediaHTML = buildLocationMediaHtml(location);
        const contentHTML = buildLocationContentHtml(location);
        const attributionRows = [
            location.publishedByUsername
                ? [currentLanguage === 'pt' ? 'Publicado por' : 'Published by', location.publishedByUsername]
                : null,
            location.modifiedByUsername
                ? [currentLanguage === 'pt' ? 'Modificado por' : 'Modified by', location.modifiedByUsername]
                : null,
            location.approvedByUsername
                ? [currentLanguage === 'pt' ? 'Aprovado por' : 'Approved by', location.approvedByUsername]
                : null
        ].filter(Boolean);

        const canSuggest = !!currentMapUser && !isEditorAdmin && !!location.databaseId;
        const footer = attributionRows.length || canSuggest
            ? `
                <footer class="deepmap-popup-footer">
                    ${attributionRows.length ? `
                        <div class="deepmap-popup-attribution">
                            ${attributionRows.map(([label, username]) => `
                                <span><small>${escapeHtml(label)}</small><a href="/u/${encodeURIComponent(username)}">@${escapeHtml(username)}</a></span>
                            `).join('')}
                        </div>
                    ` : ''}
                    ${canSuggest ? `
                        <button type="button" class="deepmap-suggest-correction" data-suggest-marker="${Number(location.databaseId)}">
                            ${currentLanguage === 'pt' ? 'Sugerir correção' : 'Suggest correction'}
                        </button>
                    ` : ''}
                </footer>
            `
            : '';

        return `
            <div class="deepmap-popup">
                ${mediaHTML}

                <div class="deepmap-popup-body">

                    <div class="deepmap-popup-category">
                        ${escapeHtml(getCategoryLabel(getCategoryForRender(location.categoryId) ?? {}))}
                    </div>

                    <h3 class="deepmap-popup-title">
                        ${escapeHtml(getLocationTitle(location))}
                    </h3>

                    ${
                        optionalInformation
                            ? `
                                <div class="deepmap-popup-info">
                                    ${optionalInformation}
                                </div>
                            `
                            : ''
                    }

                    ${
                        getLocationDescription(location)
                            ? `
                                <p class="deepmap-popup-description">
                                    ${escapeHtml(getLocationDescription(location))}
                                </p>
                            `
                            : ''
                    }

                    ${contentHTML}

                    ${footer}
                </div>
            </div>
        `;
    }

    function setupPopupMedia(marker) {
        const popupElement = marker?.getPopup?.()?.getElement?.();
        const mediaRoot = popupElement?.querySelector('.deepmap-popup-media');
        if (!mediaRoot || mediaRoot.dataset.ready === 'true') return;

        const slides = [...mediaRoot.querySelectorAll('.deepmap-popup-media-slide')];
        if (slides.length <= 1) {
            mediaRoot.dataset.ready = 'true';
            return;
        }

        const counter = mediaRoot.querySelector('[data-media-counter]');
        const previous = mediaRoot.querySelector('[data-media-prev]');
        const next = mediaRoot.querySelector('[data-media-next]');
        let activeIndex = 0;
        let touchStartX = null;

        function show(index) {
            activeIndex = (index + slides.length) % slides.length;
            slides.forEach((slide, slideIndex) => {
                slide.classList.toggle('active', slideIndex === activeIndex);
            });
            if (counter) counter.textContent = `${activeIndex + 1}/${slides.length}`;
        }

        previous?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            show(activeIndex - 1);
        });

        next?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            show(activeIndex + 1);
        });

        mediaRoot.addEventListener('touchstart', (event) => {
            touchStartX = event.touches?.[0]?.clientX ?? null;
        }, { passive: true });

        mediaRoot.addEventListener('touchend', (event) => {
            if (touchStartX === null) return;
            const endX = event.changedTouches?.[0]?.clientX ?? touchStartX;
            const delta = endX - touchStartX;
            touchStartX = null;

            if (Math.abs(delta) < 35) return;
            show(activeIndex + (delta < 0 ? 1 : -1));
        }, { passive: true });

        mediaRoot.dataset.ready = 'true';
        show(0);
    }


    function setupPopupActions(marker, location) {
        const popupElement = marker?.getPopup?.()?.getElement?.();
        const button = popupElement?.querySelector('[data-suggest-marker]');
        if (!button || button.dataset.ready === 'true') return;
        button.dataset.ready = 'true';
        button.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            marker.closePopup();
            openCommunityCorrection(location);
        });
    }


    /* ==========================================
       MARCADORES SVG
       ========================================== */

    function createLocationIcon(location) {
        const category = getCategoryForRender(location.categoryId);

        const iconUrl = location.icon ?? category?.icon;
        const markerColor = location.colorOverride ?? category?.color ?? '#22222a';

        const markerWidth = location.markerWidthOverride ?? category?.markerWidth ?? 30;
        const markerHeight = location.markerHeightOverride ?? category?.markerHeight ?? 39;
        const symbolSize = location.symbolSizeOverride ?? category?.symbolSize ?? 18;

        // Converte o tamanho do símbolo para a escala interna do SVG.
        const svgSymbolSize = (symbolSize / markerWidth) * 40;
        const svgSymbolX = (40 - svgSymbolSize) / 2;
        const svgSymbolY = 8;

        return Leaflet.divIcon({
            className: 'deepmap-marker-wrapper',

            html: `
                <div
                    class="deepmap-marker"
                    style="
                        --marker-width: ${markerWidth}px;
                        --marker-height: ${markerHeight}px;
                    "
                >
                    <svg
                        class="deepmap-marker-shape"
                        viewBox="0 0 40 52"
                        xmlns="http://www.w3.org/2000/svg"
                    >
                        <path
                            d="
                                M20 1
                                C9.5 1 1 9.5 1 20
                                C1 34 20 51 20 51
                                C20 51 39 34 39 20
                                C39 9.5 30.5 1 20 1
                                Z
                            "
                            fill="${markerColor}"
                        />

                        ${iconUrl ? `
                            <image
                                href="${escapeHtml(iconUrl)}"
                                x="${svgSymbolX}"
                                y="${svgSymbolY}"
                                width="${svgSymbolSize}"
                                height="${svgSymbolSize}"
                                preserveAspectRatio="xMidYMid meet"
                            />
                        ` : ''}
                    </svg>
                </div>
            `,

            iconSize: [markerWidth, markerHeight],

            iconAnchor: [
                markerWidth / 2,
                markerHeight
            ],

            popupAnchor: [
                0,
                -markerHeight + 4
            ]
        });
    }

    function renderLocationMarkers() {
        if (
            !map ||
            !Leaflet ||
            !Object.keys(markerLayerGroups).length
        ) {
            return;
        }

        for (const group of Object.values(markerLayerGroups)) {
            group.clearLayers();
        }

        for (const location of locations) {
            const renderCategory = getCategoryForRender(location.categoryId);

            if (
                categoryVisibility[location.categoryId] === false ||
                renderCategory?.isActive === false
            ) {
                continue;
            }

            if (
                editorMode &&
                editorTool === 'marker' &&
                editorMarkerMoved &&
                !editorShowOriginalLocation &&
                editorSelectedMarkerId !== null &&
                Number(location.databaseId) === Number(editorSelectedMarkerId)
            ) {
                continue;
            }

            const group = markerLayerGroups[location.mapLayer];

            if (!group) continue;

            const marker = Leaflet.marker(
                location.coordinates,
                {
                    icon: createLocationIcon(location)
                }
            );

            marker.bindPopup(
                buildLocationPopup(location),
                {
                    maxWidth: 360,
                    minWidth: 220,
                    className: 'deepmap-leaflet-popup'
                }
            );

            marker.on('popupopen', () => {
                setupPopupMedia(marker);
                setupPopupActions(marker, location);
            });

            // Tooltip traduzido ao passar o rato.
            marker.bindTooltip(
                getLocationTitle(location),
                {
                    direction: 'top',
                    offset: [0, -32],
                    opacity: 1,
                    className: 'deepmap-marker-tooltip'
                }
            );

            marker.on('click', (event) => {
                marker.closeTooltip();

                // No Editor 2.0, clicar num marcador que já vive na BD
                // seleciona-o para edição. Marcadores legacy continuam normais
                // até serem migrados para public.marcadores.
                if (editorMode && editorTool === 'marker' && isEditorAdmin && location.databaseId) {
                    marker.closePopup();

                    if (editorPositionMode === 'marker' && editorSelectedMarkerId !== null) {
                        const [y, x] = location.coordinates;
                        setEditorCoordinates(x, y);
                        editorPositionMode = null;
                    } else {
                        handleEditorSelectionChange(location.databaseId);
                        if (map) map.panTo(location.coordinates);
                    }

                    if (event?.originalEvent) {
                        Leaflet.DomEvent.stopPropagation(event.originalEvent);
                    }
                }
            });

            marker.addTo(group);
        }
    }

    function createMapLabelIcon(label) {
        const text = getMapLabelText(label);
        const visibleText = label.uppercase ? text.toLocaleUpperCase(currentLanguage === 'pt' ? 'pt-PT' : 'en-GB') : text;

        const fontSize = Number(label.fontSize ?? 34);
        const hitWidth = Math.max(80, Math.min(460, Math.round(Math.max(1, visibleText.length) * fontSize * 0.64)));
        const hitHeight = Math.max(28, Math.round(fontSize * 1.35));

        return Leaflet.divIcon({
            className: 'deepmap-zone-label-wrapper',
            html: `
                <div
                    class="deepmap-zone-label"
                    style="
                        --zone-label-color: ${escapeHtml(label.color ?? '#E8D7A4')};
                        --zone-label-size: ${fontSize}px;
                        --zone-label-weight: ${Number(label.fontWeight ?? 700)};
                        --zone-label-opacity: ${Number(label.opacity ?? 0.82)};
                    "
                >${escapeHtml(visibleText)}</div>
            `,
            iconSize: [hitWidth, hitHeight],
            iconAnchor: [hitWidth / 2, hitHeight / 2]
        });
    }

    function renderMapLabels() {
        if (!map || !Leaflet || !Object.keys(mapLabelLayerGroups).length) return;

        for (const group of Object.values(mapLabelLayerGroups)) {
            group.clearLayers();
        }

        for (const label of mapLabels) {
            const group = mapLabelLayerGroups[label.mapLayer];
            if (!group) continue;

            if (
                editorMode &&
                editorTool === 'label' &&
                editorLabelMoved &&
                !editorShowOriginalLabelLocation &&
                editorSelectedLabelId !== null &&
                Number(label.databaseId) === Number(editorSelectedLabelId)
            ) {
                continue;
            }

            const editable =
                editorMode &&
                editorTool === 'label' &&
                isEditorAdmin &&
                label.databaseId;

            const labelMarker = Leaflet.marker(label.coordinates, {
                icon: createMapLabelIcon(label),
                interactive: editable,
                keyboard: editable,
                zIndexOffset: editable ? 2000 : 0
            });

            if (editable) {
                labelMarker.on('click', (event) => {
                    if (editorPositionMode === 'label' && editorSelectedLabelId !== null) {
                        const [y, x] = label.coordinates;
                        setEditorCoordinates(x, y);
                        editorPositionMode = null;
                    } else {
                        handleEditorLabelSelection(label.databaseId);
                        if (map) map.panTo(label.coordinates);
                    }

                    if (event?.originalEvent) {
                        Leaflet.DomEvent.stopPropagation(event.originalEvent);
                    }
                });
            }

            labelMarker.addTo(group);
        }
    }



    /* ==========================================
       EDITOR 2.0
       ========================================== */

    let editorMode = $state(false);
    let editorTool = $state('marker');
    let editorMarker = null;
    let editorLabelPreview = null;
    let editorPointMarker = null;

    // Comunicação entre o mapa Leaflet e a ferramenta atualmente aberta.
    let editorPoint = $state(null);
    let editorSelectedMarkerId = $state(null);
    let editorSelectedLabelId = $state(null);
    let editorMarkerMoved = $state(false);
    let editorShowOriginalLocation = $state(false);
    let editorLabelMoved = $state(false);
    let editorShowOriginalLabelLocation = $state(false);
    let editorPositionMode = $state(null);
    let editorPointRevision = 0;

    let editorToolText = $derived(currentLanguage === 'pt'
        ? { markers: 'Marcadores', labels: 'Títulos de zona', categories: 'Categorias e ícones', moderation: 'Moderação' }
        : { markers: 'Markers', labels: 'Zone titles', categories: 'Categories & icons', moderation: 'Moderation' }
    );

    function getCategoryForRender(categoryId) {
        return categories[categoryId];
    }

    function clearEditorPointMarker() {
        if (editorPointMarker && map) map.removeLayer(editorPointMarker);
        editorPointMarker = null;
    }

    function showEditorPointMarker(x, y) {
        clearEditorPointMarker();
        if (!map || !Leaflet || editorTool !== 'label') return;

        editorPointMarker = Leaflet.circleMarker([Number(y), Number(x)], {
            radius: 5,
            color: '#f0a24a',
            weight: 2,
            fillColor: '#f0a24a',
            fillOpacity: 0.75,
            interactive: false,
            bubblingMouseEvents: false,
            pane: 'markerPane'
        }).addTo(map);
    }

    function setEditorCoordinates(x, y) {
        editorPoint = {
            x: Number(x),
            y: Number(y),
            revision: ++editorPointRevision
        };

        if (editorTool === 'label') {
            showEditorPointMarker(x, y);
        }
    }

    function clearEditorMarkerPreview() {
        if (editorMarker && map) map.removeLayer(editorMarker);
        editorMarker = null;
    }

    function clearEditorLabelPreview() {
        if (editorLabelPreview && map) map.removeLayer(editorLabelPreview);
        editorLabelPreview = null;
    }

    function previewEditorMarker(marker, options = {}) {
        if (options.clear || !marker || !map || !Leaflet) {
            clearEditorMarkerPreview();
            return;
        }

        const x = Number(marker.coordinateX);
        const y = Number(marker.coordinateY);
        if (!Number.isFinite(x) || !Number.isFinite(y)) return;

        const location = {
            databaseId: marker.databaseId ?? marker.id ?? null,
            id: 'editor-preview',
            slug: 'editor-preview',
            mapLayer: marker.mapLayer || activeMapLayer,
            categoryId: marker.categoryId,
            colorOverride: PREVIEW_MARKER_COLOR,
            coordinates: [y, x]
        };

        if (!editorMarker) {
            editorMarker = Leaflet.marker([y, x], {
                icon: createLocationIcon(location),
                zIndexOffset: 10000,
                opacity: PREVIEW_MARKER_OPACITY,
                interactive: false,
                keyboard: false
            }).addTo(map);
        } else {
            editorMarker.setLatLng([y, x]);
            editorMarker.setIcon(createLocationIcon(location));
            editorMarker.setOpacity(PREVIEW_MARKER_OPACITY);
        }

        if (options.pan) map.panTo([y, x]);
    }

    function previewEditorMapLabel(label, options = {}) {
        if (options.clear || !label || !map || !Leaflet) {
            clearEditorLabelPreview();
            return;
        }

        const x = Number(label.coordinateX);
        const y = Number(label.coordinateY);
        if (!Number.isFinite(x) || !Number.isFinite(y)) return;

        const normalised = {
            ...label,
            text: { en: label.textEn || '', pt: label.textPt || '' },
            coordinates: [y, x]
        };

        if (!editorLabelPreview) {
            editorLabelPreview = Leaflet.marker([y, x], {
                icon: createMapLabelIcon(normalised),
                interactive: false,
                keyboard: false,
                zIndexOffset: 12000
            }).addTo(map);
        } else {
            editorLabelPreview.setLatLng([y, x]);
            editorLabelPreview.setIcon(createMapLabelIcon(normalised));
        }

        if (options.pan) map.panTo([y, x]);
    }

    function handleEditorSelectionChange(markerId) {
        editorSelectedMarkerId = markerId;
        editorMarkerMoved = false;
        editorShowOriginalLocation = false;
        editorPositionMode = null;
        renderLocationMarkers();
    }

    function handleEditorPositionMode(tool, active) {
        editorPositionMode = active === true ? tool : null;
    }

    function handleEditorMoveStateChange(moved) {
        editorMarkerMoved = moved === true;
        renderLocationMarkers();
    }

    function handleEditorOriginalVisibilityChange(visible) {
        editorShowOriginalLocation = visible === true;
        renderLocationMarkers();
    }


    function handleEditorLabelSelection(labelId) {
        editorSelectedLabelId = labelId;
        editorLabelMoved = false;
        editorShowOriginalLabelLocation = false;
        editorPositionMode = null;
        editorPoint = null;
        clearEditorPointMarker();
        renderMapLabels();
    }

    function handleEditorLabelMoveStateChange(moved) {
        editorLabelMoved = moved === true;
        renderMapLabels();
    }

    function handleEditorLabelOriginalVisibilityChange(visible) {
        editorShowOriginalLabelLocation = visible === true;
        renderMapLabels();
    }

    async function handleEditorDataChanged(event) {
        await loadGameMapData();
        renderLocationMarkers();
        renderMapLabels();

        if (event?.action === 'save' || event?.action === 'delete') {
            editorSelectedMarkerId = null;
            editorPoint = null;
            editorMarkerMoved = false;
            editorShowOriginalLocation = false;
            editorPositionMode = null;
            clearEditorMarkerPreview();
            renderLocationMarkers();
        }

        if (event?.action === 'save-label' || event?.action === 'delete-label') {
            editorSelectedLabelId = null;
            editorPoint = null;
            editorLabelMoved = false;
            editorShowOriginalLabelLocation = false;
            editorPositionMode = null;
            clearEditorLabelPreview();
            clearEditorPointMarker();
            renderMapLabels();
        }

    }

    function setEditorTool(tool) {
        editorTool = tool;
        editorPoint = null;
        editorSelectedMarkerId = null;
        editorSelectedLabelId = null;
        editorMarkerMoved = false;
        editorShowOriginalLocation = false;
        editorLabelMoved = false;
        editorShowOriginalLabelLocation = false;
        editorPositionMode = null;
        clearEditorMarkerPreview();
        clearEditorLabelPreview();
        clearEditorPointMarker();
        renderLocationMarkers();
        renderMapLabels();
    }

    function toggleEditor() {
        if (!isEditorAdmin) return;

        editorMode = !editorMode;

        if (!editorMode) {
            editorPoint = null;
            editorSelectedMarkerId = null;
            editorSelectedLabelId = null;
            editorMarkerMoved = false;
            editorShowOriginalLocation = false;
            editorLabelMoved = false;
            editorShowOriginalLabelLocation = false;
            editorPositionMode = null;
            clearEditorMarkerPreview();
            clearEditorLabelPreview();
            clearEditorPointMarker();
            renderLocationMarkers();
            renderMapLabels();
        }
    }


    /* ==========================================
       CONTRIBUTIONS — USERS (OUTSIDE EDITOR)
       ========================================== */

    let communityPanelOpen = $state(false);
    let communityRequestMode = $state('create');
    let communityRequestMarker = $state(null);
    let communityRequestRevision = $state(0);
    let communityPoint = $state(null);
    let communityPointRevision = $state(0);
    let communityPositionMode = $state(false);
    let communityPreviewMarker = null;

    function clearCommunityPreview() {
        if (communityPreviewMarker && map) map.removeLayer(communityPreviewMarker);
        communityPreviewMarker = null;
    }

    function previewCommunityMarker(marker, options = {}) {
        if (options.clear || !marker || !map || !Leaflet) {
            clearCommunityPreview();
            return;
        }
        const x = Number(marker.coordinateX);
        const y = Number(marker.coordinateY);
        if (!Number.isFinite(x) || !Number.isFinite(y)) return;
        const location = {
            id: 'community-preview',
            slug: 'community-preview',
            mapLayer: marker.mapLayer || activeMapLayer,
            categoryId: marker.categoryId,
            colorOverride: PREVIEW_MARKER_COLOR,
            coordinates: [y, x]
        };
        if (!communityPreviewMarker) {
            communityPreviewMarker = Leaflet.marker([y, x], {
                icon: createLocationIcon(location),
                zIndexOffset: 9000,
                opacity: PREVIEW_MARKER_OPACITY,
                interactive: false,
                keyboard: false
            }).addTo(map);
        } else {
            communityPreviewMarker.setLatLng([y, x]);
            communityPreviewMarker.setIcon(createLocationIcon(location));
            communityPreviewMarker.setOpacity(PREVIEW_MARKER_OPACITY);
        }
    }

    function setCommunityCoordinates(x, y) {
        communityPoint = { x: Number(x), y: Number(y), revision: ++communityPointRevision };
    }

    function openCommunityCreate() {
        if (!currentMapUser || isEditorAdmin) return;
        communityRequestMode = 'create';
        communityRequestMarker = null;
        communityRequestRevision += 1;
        communityPanelOpen = true;
        communityPositionMode = false;
        clearCommunityPreview();
    }

    function openCommunityMine() {
        if (!currentMapUser || isEditorAdmin) return;
        communityRequestMode = 'mine';
        communityRequestMarker = null;
        communityRequestRevision += 1;
        communityPanelOpen = true;
        communityPositionMode = false;
        clearCommunityPreview();
    }

    function openCommunityCorrection(location) {
        if (!currentMapUser || isEditorAdmin || !location?.databaseId) return;
        communityRequestMode = 'correction';
        communityRequestMarker = location;
        communityRequestRevision += 1;
        communityPanelOpen = true;
        communityPositionMode = false;
        clearCommunityPreview();
    }

    function closeCommunityPanel() {
        communityPanelOpen = false;
        communityPositionMode = false;
        communityPoint = null;
        clearCommunityPreview();
    }

    async function handleCommunitySubmitted() {
        // Queue/status changed, but official markers only change after moderation approval.
    }


    /* ==========================================
       INICIALIZAÇÃO DO MAPA
       ========================================== */

    onMount(async () => {
        // A língua escolhida mantém-se ao navegar entre mapa e perfil.
        currentLanguage = getSiteLanguage();

        // Falha fechada: sem sessão/RPC/admin, o Editor nem sequer aparece.
        void loadEditorAccess();

        // Primeiro tentamos Supabase. Enquanto a migração estiver incompleta,
        // cada coleção em falta continua a usar os ficheiros legacy.
        await loadGameMapData();

        const L = await import('leaflet');

        await import('leaflet/dist/leaflet.css');

        Leaflet = L;

        const surfaceDefinition = mapDefinitions.surface;
        const bounds = getMapBounds(surfaceDefinition);

        map = L.map(
            mapContainer,
            {
                crs: L.CRS.Simple,
                maxBounds: bounds,
                maxBoundsViscosity: 0.8,
                attributionControl: false,
                minZoom: -3,
                maxZoom: 2,
                zoomSnap: 0.25
            }
        );

        mapImageOverlay = L.imageOverlay(
            surfaceDefinition.image,
            bounds
        ).addTo(map);


        /* MARCA D'ÁGUA */

        const LogoWatermark = L.Control.extend({
            options: {
                position: 'bottomright'
            },

            onAdd: function () {
                const div = L.DomUtil.create(
                    'div',
                    'map-watermark'
                );

                div.innerHTML = `
                    <img
                        src="/brand/logo.png"
                        alt="DeepMap Logo"
                    />
                `;

                return div;
            }
        });

        map.addControl(new LogoWatermark());


        /* LAYERS DOS MARCADORES */

        setupMarkerLayers();
        renderLocationMarkers();
        renderMapLabels();


        /* CLIQUE NO MAPA — EDITOR */

        map.on('click', (e) => {
            const x = Math.round(e.latlng.lng);
            const y = Math.round(e.latlng.lat);

            if (communityPanelOpen && communityPositionMode && currentMapUser && !isEditorAdmin) {
                setCommunityCoordinates(x, y);
                communityPositionMode = false;
                return;
            }

            if (!editorMode || !isEditorAdmin) return;

            if (editorTool === 'marker') {
                if (editorSelectedMarkerId !== null && editorPositionMode !== 'marker') return;
                setEditorCoordinates(x, y);
                if (editorSelectedMarkerId !== null) editorPositionMode = null;
                return;
            }

            if (editorTool === 'label') {
                if (editorSelectedLabelId !== null && editorPositionMode !== 'label') return;
                setEditorCoordinates(x, y);
                if (editorSelectedLabelId !== null) editorPositionMode = null;
            }
        });

        mapImageOverlay.on('load', () => {
            map.fitBounds(bounds);
        });

        map.fitBounds(bounds);

        setTimeout(() => {
            if (map) {
                map.invalidateSize();
            }
        }, 250);
    });
</script>


<div class="app-container">

    <!-- CONTROLO DO MENU MOBILE -->
    <!-- Mantém esta estrutura: o CSS controla abrir/fechar. -->

    <input
        type="checkbox"
        id="mobile-menu-toggle"
        class="mobile-menu-checkbox"
    />


    <!-- SUBHEADER DO JOGO -->

    <header class="game-subheader">

        <label
            for="mobile-menu-toggle"
            class="mobile-toggle"
            aria-label={currentTexts.open_menu}
        >
            <span class="menu-icon">☰</span>
            <span class="close-icon">✕</span>
        </label>

        <div class="game-brand">
            <span class="game-title">Elden Ring</span>
        </div>

        <div class="subheader-actions">
            <div class="checklist-status">
                {currentTexts.checklist}
                <span>(0%)</span>
            </div>
        </div>

    </header>


    <!-- EDITOR — só é mostrado a administradores confirmados -->

    {#if editorAccessChecked && isEditorAdmin}
    <div class="editor-ui">

        <button
            id="editor-toggle"
            class="editor-toggle"
            class:active={editorMode}
            onclick={toggleEditor}
        >
            {currentTexts.editor}
        </button>

        {#if editorMode}
            <div class="editor-tool-tabs" role="tablist" aria-label="Editor">
                <button
                    type="button"
                    class:active={editorTool === 'marker'}
                    onclick={() => setEditorTool('marker')}
                >
                    {editorToolText.markers}
                </button>
                <button
                    type="button"
                    class:active={editorTool === 'label'}
                    onclick={() => setEditorTool('label')}
                >
                    {editorToolText.labels}
                </button>
                <button
                    type="button"
                    class:active={editorTool === 'category'}
                    onclick={() => setEditorTool('category')}
                >
                    {editorToolText.categories}
                </button>
                <button
                    type="button"
                    class:active={editorTool === 'moderation'}
                    onclick={() => setEditorTool('moderation')}
                >
                    {editorToolText.moderation}
                </button>
            </div>

            <div class="editor-scroll-area">
                {#if editorTool === 'marker'}
                    <MarkerEditorPanel
                        gameId={GAME_ID}
                        language={currentLanguage}
                        active={editorMode}
                        point={editorPoint}
                        selectedMarkerId={editorSelectedMarkerId}
                        {categories}
                        {categoryGroups}
                        {mapDefinitions}
                        onChanged={handleEditorDataChanged}
                        onPreview={previewEditorMarker}
                        onSelectionChange={handleEditorSelectionChange}
                        positionModeActive={editorPositionMode === 'marker'}
                        onPositionModeChange={(active) => handleEditorPositionMode('marker', active)}
                        onMoveStateChange={handleEditorMoveStateChange}
                        onOriginalVisibilityChange={handleEditorOriginalVisibilityChange}
                    />
                {:else if editorTool === 'label'}
                    <MapLabelEditorPanel
                        gameId={GAME_ID}
                        language={currentLanguage}
                        active={editorMode}
                        point={editorPoint}
                        selectedLabelId={editorSelectedLabelId}
                        {mapDefinitions}
                        onChanged={handleEditorDataChanged}
                        onPreview={previewEditorMapLabel}
                        onSelectionChange={handleEditorLabelSelection}
                        positionModeActive={editorPositionMode === 'label'}
                        onPositionModeChange={(active) => handleEditorPositionMode('label', active)}
                        onMoveStateChange={handleEditorLabelMoveStateChange}
                        onOriginalVisibilityChange={handleEditorLabelOriginalVisibilityChange}
                    />
                {:else if editorTool === 'category'}
                    <CategoryManagerPanel
                        gameId={GAME_ID}
                        language={currentLanguage}
                        {categories}
                        {categoryGroups}
                        standalone={true}
                        onChanged={handleEditorDataChanged}
                    />
                {:else}
                    <ModerationPanel
                        gameId={GAME_ID}
                        language={currentLanguage}
                        active={editorMode}
                        {categories}
                        {locations}
                        onChanged={handleEditorDataChanged}
                        onPreview={previewEditorMarker}
                    />
                {/if}
            </div>
        {/if}
    </div>
    {/if}

    {#if communityPanelOpen && currentMapUser && !isEditorAdmin}
        <CommunityMarkerPanel
            gameId={GAME_ID}
            language={currentLanguage}
            active={communityPanelOpen}
            userId={currentMapUser.id}
            requestMode={communityRequestMode}
            requestMarker={communityRequestMarker}
            requestRevision={communityRequestRevision}
            point={communityPoint}
            {categories}
            {categoryGroups}
            {mapDefinitions}
            positionModeActive={communityPositionMode}
            onPositionModeChange={(active) => communityPositionMode = active}
            onPreview={previewCommunityMarker}
            onClose={closeCommunityPanel}
            onSubmitted={handleCommunitySubmitted}
        />
    {/if}


    <!-- CONTEÚDO PRINCIPAL -->

    <div class="body-container">

        <!-- SIDEBAR DESKTOP -->

        <aside class="desktop-sidebar">

            <div class="sidebar-content">


                {#if editorAccessChecked && currentMapUser && !isEditorAdmin}
                    <div class="community-sidebar-actions">
                        <button type="button" onclick={openCommunityCreate}>＋ {currentLanguage === 'pt' ? 'Adicionar marcador' : 'Add marker'}</button>
                        <button type="button" onclick={openCommunityMine}>{currentLanguage === 'pt' ? 'As minhas contribuições' : 'My contributions'}</button>
                    </div>
                {/if}

                <h2>{currentTexts.filters}</h2>

                <!-- SHOW ALL / HIDE ALL -->

                <div
                    class="filter-actions"
                    role="group"
                    aria-label={currentTexts.filters}
                >
                    <button
                        type="button"
                        class="filter-action"
                        onclick={() => setAllCategoryVisibility(true)}
                    >
                        {currentTexts.show_all}
                    </button>

                    <button
                        type="button"
                        class="filter-action"
                        onclick={() => setAllCategoryVisibility(false)}
                    >
                        {currentTexts.hide_all}
                    </button>
                </div>


                <!-- CATEGORIAS -->

                {#each filterGroups as group (group.id)}

                    <div class="filter-group">

                        <h3>
                            {getGroupLabel(group)}
                        </h3>

                        {#each group.categories as category (category.id)}

                            <button
                                type="button"
                                class="filter-row"
                                class:inactive={categoryVisibility[category.id] === false}
                                aria-pressed={categoryVisibility[category.id] !== false}
                                onclick={() => toggleCategory(category.id)}
                            >

                                <span
                                    class="filter-icon"
                                    style={`--category-color: ${category.color};`}
                                    aria-hidden="true"
                                >
                                    {#if category.icon}

                                        <img
                                            src={category.icon}
                                            alt=""
                                        />

                                    {:else}

                                        <span class="filter-icon-placeholder"></span>

                                    {/if}
                                </span>

                                <span class="filter-text">
                                    {getCategoryLabel(category)}
                                </span>

                            </button>

                        {/each}

                    </div>

                {/each}

            </div>
        </aside>


        <!-- MAPA -->

        <main class="map-wrapper">

            <div
                bind:this={mapContainer}
                class="map-element"
            ></div>

        </main>

    </div>


    <!-- MENU MOBILE — ESTRUTURA ORIGINAL -->

    <div class="mobile-menu-layer">

        <label
            for="mobile-menu-toggle"
            class="mobile-backdrop"
            aria-label={currentTexts.close_menu}
        ></label>


        <aside class="mobile-sidebar">

            <div class="mobile-sidebar-header">

                <h2>{currentTexts.filters}</h2>

                <label
                    for="mobile-menu-toggle"
                    class="mobile-close"
                    aria-label={currentTexts.close_menu}
                >
                    ✕
                </label>

            </div>


            <div class="sidebar-content">


                {#if editorAccessChecked && currentMapUser && !isEditorAdmin}
                    <div class="community-sidebar-actions">
                        <button type="button" onclick={openCommunityCreate}>＋ {currentLanguage === 'pt' ? 'Adicionar marcador' : 'Add marker'}</button>
                        <button type="button" onclick={openCommunityMine}>{currentLanguage === 'pt' ? 'As minhas contribuições' : 'My contributions'}</button>
                    </div>
                {/if}

                <!-- SHOW ALL / HIDE ALL MOBILE -->

                <div
                    class="filter-actions"
                    role="group"
                    aria-label={currentTexts.filters}
                >

                    <button
                        type="button"
                        class="filter-action"
                        onclick={() => setAllCategoryVisibility(true)}
                    >
                        {currentTexts.show_all}
                    </button>

                    <button
                        type="button"
                        class="filter-action"
                        onclick={() => setAllCategoryVisibility(false)}
                    >
                        {currentTexts.hide_all}
                    </button>

                </div>


                <!-- CATEGORIAS MOBILE -->

                {#each filterGroups as group (group.id)}

                    <div class="filter-group">

                        <h3>
                            {getGroupLabel(group)}
                        </h3>

                        {#each group.categories as category (category.id)}

                            <button
                                type="button"
                                class="filter-row"
                                class:inactive={categoryVisibility[category.id] === false}
                                aria-pressed={categoryVisibility[category.id] !== false}
                                onclick={() => toggleCategory(category.id)}
                            >

                                <span
                                    class="filter-icon"
                                    style={`--category-color: ${category.color};`}
                                    aria-hidden="true"
                                >
                                    {#if category.icon}

                                        <img
                                            src={category.icon}
                                            alt=""
                                        />

                                    {:else}

                                        <span class="filter-icon-placeholder"></span>

                                    {/if}
                                </span>

                                <span class="filter-text">
                                    {getCategoryLabel(category)}
                                </span>

                            </button>

                        {/each}

                    </div>

                {/each}

            </div>

        </aside>

    </div>

</div>


<style>

    /* ==========================================
       BASE
       ========================================== */

    /* Bloquear o scroll EXCLUSIVAMENTE quando o mapa está nesta rota. */
    :global(html:has(.app-container)),
    :global(body:has(.app-container)) {
        height: 100%;
        overflow: hidden;
    }

    .app-container {
        width: 100vw;
        height: 100vh;
        height: 100dvh;
        overflow: hidden;
        background: #0b0b0e;
    }


    /* ==========================================
       SUBHEADER DO JOGO
       ========================================== */

    .game-subheader {
        position: fixed;
        top: var(--deepmap-site-header-height, 72px);
        left: 0;
        right: 0;
        height: var(--deepmap-game-subheader-height, 54px);
        background: #16161a;
        border-bottom: 1px solid #2a2a30;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 16px;
        box-sizing: border-box;
        z-index: 30000;
    }

    .game-brand {
        display: flex;
        align-items: center;
        min-width: 0;
    }

    .game-title {
        font-size: 1.08rem;
        font-weight: 700;
        color: #d8b86f;
        letter-spacing: 0.7px;
    }

    .subheader-actions {
        display: flex;
        align-items: center;
        gap: 12px;
    }

    .checklist-status {
        font-size: 0.88rem;
        color: #a0a0a0;
    }

    .checklist-status span {
        color: #c8a355;
        font-weight: 600;
    }


    /* ==========================================
       BOTÃO MOBILE
       ========================================== */

    .mobile-menu-checkbox {
        display: none;
    }

    .mobile-toggle {
        display: none;
        align-items: center;
        justify-content: center;

        width: 48px;
        height: 48px;
        padding: 0;

        background: transparent;
        border: 0;

        color: #c8a355;
        font-size: 28px;

        cursor: pointer;
        touch-action: manipulation;
        z-index: 10001;
    }

    .menu-icon,
    .close-icon {
        display: block;
        line-height: 1;
    }

    .close-icon {
        display: none;
    }


    /* ==========================================
       EDITOR 2.0
       ========================================== */

    .editor-ui {
        position: fixed !important;
        top: calc(var(--deepmap-site-header-height, 72px) + var(--deepmap-game-subheader-height, 54px) + 12px) !important;
        right: 16px !important;
        bottom: 12px !important;
        width: min(430px, calc(100vw - 32px));
        max-height: calc(100vh - var(--deepmap-site-header-height, 72px) - var(--deepmap-game-subheader-height, 54px) - 24px);
        display: flex;
        flex-direction: column;
        min-height: 0;
        z-index: 999999 !important;
        pointer-events: none;
    }

    .editor-scroll-area {
        flex: 1 1 auto;
        min-height: 0;
        margin-top: 8px;
        padding-right: 4px;
        overflow-y: auto;
        overscroll-behavior: contain;
        scrollbar-gutter: stable;
        pointer-events: auto;
    }

    .editor-scroll-area::-webkit-scrollbar { width: 8px; }
    .editor-scroll-area::-webkit-scrollbar-track { background: rgba(20,20,24,.7); border-radius: 999px; }
    .editor-scroll-area::-webkit-scrollbar-thumb { background: rgba(200,163,85,.5); border-radius: 999px; }
    .editor-scroll-area::-webkit-scrollbar-thumb:hover { background: rgba(200,163,85,.72); }

    .editor-toggle {
        display: block;
        margin-left: auto;
        padding: 10px 16px;
        background: #16161a;
        border: 1px solid #c8a355;
        border-radius: 6px;
        color: #c8a355;
        font-size: 0.78rem;
        font-weight: 700;
        letter-spacing: 0.5px;
        cursor: pointer;
        box-shadow: 0 4px 15px rgba(0,0,0,.4);
        pointer-events: auto;
        transition: background .2s, color .2s, box-shadow .2s;
    }

    .editor-toggle:hover { background: #22222a; }
    .editor-toggle.active {
        background: #c8a355;
        color: #111116;
        box-shadow: 0 0 0 2px rgba(200,163,85,.15), 0 5px 20px rgba(0,0,0,.5);
    }

    .editor-tool-tabs {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 6px;
        margin-top: 8px;
        padding: 6px;
        border: 1px solid rgba(200,163,85,.45);
        border-radius: 7px;
        background: rgba(15,15,19,.96);
        pointer-events: auto;
    }

    .editor-tool-tabs button {
        padding: 8px 9px;
        border: 1px solid #39342a;
        border-radius: 5px;
        background: #17171c;
        color: #aaa8a2;
        font-size: .7rem;
        font-weight: 800;
        cursor: pointer;
    }

    .editor-tool-tabs button.active {
        border-color: #c8a355;
        background: rgba(200,163,85,.14);
        color: #e6c878;
    }

    :global(.deepmap-zone-label-wrapper) {
        background: transparent !important;
        border: 0 !important;
    }

    :global(.deepmap-zone-label) {
        position: absolute;
        left: 50%;
        top: 50%;
        transform: translate(-50%, -50%);
        width: max-content;
        max-width: 420px;
        color: var(--zone-label-color, #E8D7A4);
        opacity: var(--zone-label-opacity, .82);
        font-size: var(--zone-label-size, 34px);
        font-weight: var(--zone-label-weight, 700);
        line-height: 1;
        letter-spacing: .06em;
        text-align: center;
        white-space: nowrap;
        text-shadow: 0 2px 4px rgba(0,0,0,.9), 0 0 12px rgba(0,0,0,.65);
        pointer-events: none;
        user-select: none;
    }

    :global(.deepmap-editor-preview-popup .leaflet-popup-content-wrapper) {
        outline: 1px solid rgba(200,163,85,.55);
    }


    /* ==========================================
       BODY / MAPA
       ========================================== */

    .body-container {
        position: fixed;

        top: calc(var(--deepmap-site-header-height, 72px) + var(--deepmap-game-subheader-height, 54px));
        left: 0;
        right: 0;
        bottom: 0;

        overflow: hidden;
        display: flex;
    }


    /* ==========================================
       SIDEBAR DESKTOP
       ========================================== */

    .desktop-sidebar {
        position: fixed;

        top: calc(var(--deepmap-site-header-height, 72px) + var(--deepmap-game-subheader-height, 54px));
        left: 0;
        bottom: 0;

        width: 300px;

        background: #16161a;
        border-right: 1px solid #2a2a30;

        box-sizing: border-box;
        z-index: 9000;
        overflow: hidden;
    }

    .sidebar-content {
        padding: 20px;

        overflow-y: auto;
        height: 100%;

        box-sizing: border-box;
    }

    .desktop-sidebar h2 {
        font-size: 1.1rem;
        color: #c8a355;

        margin-top: 0;
        border-bottom: 1px solid #2a2a30;
        padding-bottom: 8px;
    }

    .filter-group {
        margin-bottom: 20px;
    }

    .filter-group h3 {
        font-size: 0.9rem;
        color: #888;

        text-transform: uppercase;
        letter-spacing: 0.5px;

        margin-bottom: 10px;
    }


    /* ==========================================
       FILTROS — v1.0.28
       ========================================== */

    .filter-actions {
        display: flex;
        gap: 8px;
        margin: 0 0 22px;
    }

    .filter-action {
        flex: 1;
        min-width: 0;

        padding: 8px 6px;

        background: #22222a;
        border: 1px solid #353541;
        border-radius: 5px;

        color: #c8a355;

        font: inherit;
        font-size: 0.78rem;
        font-weight: 700;

        cursor: pointer;

        transition:
            background 0.15s ease,
            border-color 0.15s ease;
    }

    .filter-action:hover {
        background: #2c2c37;
        border-color: #c8a355;
    }

    .filter-row {
        width: 100%;
        min-height: 36px;

        display: flex;
        align-items: center;
        gap: 10px;

        margin-bottom: 3px;
        padding: 5px 7px;

        background: transparent;
        border: 0;
        border-radius: 5px;

        color: #e0e0e0;
        text-align: left;

        font: inherit;
        font-size: 0.92rem;
        line-height: 1.35;

        cursor: pointer;

        transition:
            background 0.15s ease,
            opacity 0.15s ease;
    }

    .filter-row:hover {
        background: #25252d;
    }

    .filter-action:focus-visible,
    .filter-row:focus-visible {
        outline: 2px solid #c8a355;
        outline-offset: 2px;
    }

    .filter-icon {
        width: 24px;
        height: 24px;
        flex: 0 0 24px;

        display: flex;
        align-items: center;
        justify-content: center;
    }

    .filter-icon img {
        display: block;
        width: 23px;
        height: 23px;
        object-fit: contain;
    }

    /* Substituto provisório para categorias sem PNG. */

    .filter-icon-placeholder {
        width: 10px;
        height: 10px;

        border-radius: 50%;
        background: var(--category-color, #888899);

        box-shadow:
            0 0 0 2px rgba(255, 255, 255, 0.07);
    }

    .filter-row.inactive {
        opacity: 0.38;
    }

    .filter-row.inactive .filter-text {
        text-decoration: line-through;
    }


    /* ==========================================
       MAPA
       ========================================== */

    .map-wrapper {
        position: absolute;

        top: 0;
        left: 300px;
        right: 0;
        bottom: 0;

        background: #0b0b0e;
    }

    .map-element {
        position: absolute;

        top: 0;
        left: 0;
        right: 0;
        bottom: 0;

        background: #0b0b0e;
    }


    /* ==========================================
       MARCADORES SVG
       ========================================== */

    :global(.deepmap-marker-wrapper) {
        background: transparent !important;
        border: 0 !important;
    }

    :global(.deepmap-marker) {
        width: var(--marker-width);
        height: var(--marker-height);

        transition: transform 0.15s ease;
    }

    :global(.deepmap-marker-shape) {
        width: 100%;
        height: 100%;

        display: block;
        overflow: visible;

        filter:
            drop-shadow(
                0 1px 2px rgba(0, 0, 0, 0.8)
            );
    }

    :global(.deepmap-marker:hover) {
        transform: scale(1.12);
    }


    /* ==========================================
       TOOLTIP
       ========================================== */

    :global(.deepmap-marker-tooltip) {
        background: #16161a;
        color: #ffffff;

        border: 1px solid #2a2a30;
        border-radius: 5px;

        padding: 5px 8px;

        font-size: 0.78rem;
        font-weight: 600;

        box-shadow:
            0 3px 8px rgba(0, 0, 0, 0.45);
    }

    :global(.deepmap-marker-tooltip::before) {
        border-top-color: #16161a;
    }


    /* ==========================================
       POPUP DE LOCALIZAÇÕES
       ========================================== */

    :global(.deepmap-leaflet-popup .leaflet-popup-content-wrapper) {
        background: #16161a;
        color: #e7e7ea;

        padding: 0;
        border-radius: 10px;

        border:
            1px solid rgba(200, 163, 85, 0.45);

        overflow: hidden;

        box-shadow:
            0 12px 35px rgba(0, 0, 0, 0.7);
    }

    :global(.deepmap-leaflet-popup .leaflet-popup-content) {
        margin: 0;
        width: auto !important;
    }

    :global(.deepmap-leaflet-popup .leaflet-popup-tip) {
        background: #16161a;
    }

    :global(.deepmap-leaflet-popup .leaflet-popup-close-button) {
        color: #ffffff !important;
        background: rgba(0, 0, 0, 0.55) !important;

        width: 28px !important;
        height: 28px !important;
        line-height: 27px !important;

        border-radius: 50%;

        top: 7px !important;
        right: 7px !important;

        z-index: 5;
        font-size: 18px !important;
    }

    :global(.deepmap-popup) {
        width: auto;
        min-width: 220px;
        max-width: min(340px, calc(100vw - 48px));
        overflow-wrap: anywhere;
    }

    :global(.deepmap-popup-media) {
        position: relative;
        width: min(340px, calc(100vw - 48px));
        max-width: 100%;
        aspect-ratio: 16 / 9;
        overflow: hidden;
        background: #0b0b0e;
    }

    :global(.deepmap-popup-media-slide) {
        position: absolute;
        inset: 0;
        display: none;
        width: 100%;
        height: 100%;
    }

    :global(.deepmap-popup-media-slide.active) {
        display: grid;
        place-items: center;
    }

    :global(.deepmap-popup-media-image) {
        max-width: 100%;
        max-height: 100%;
        width: auto;
        height: auto;
        display: block;
        object-fit: contain;
        image-orientation: from-image;
    }

    :global(.deepmap-popup-video-slide) {
        background: #09090c;
    }

    :global(.deepmap-popup-video-slide iframe) {
        width: 100%;
        height: 100%;
        display: block;
        border: 0;
    }

    :global(.deepmap-popup-video-link) {
        width: 100%;
        height: 100%;
        display: grid;
        place-items: center;
        color: #d8b86f;
        font-size: .82rem;
        font-weight: 800;
        text-decoration: none;
        background:
            radial-gradient(circle at center, rgba(200,163,85,.09), transparent 65%),
            #0b0b0e;
    }

    :global(.deepmap-popup-media-arrow) {
        position: absolute;
        top: 50%;
        z-index: 4;
        width: 32px;
        height: 40px;
        display: grid;
        place-items: center;
        transform: translateY(-50%);
        border: 1px solid rgba(255,255,255,.14);
        border-radius: 6px;
        background: rgba(8,8,10,.74);
        color: #fff;
        font-size: 1.35rem;
        line-height: 1;
        cursor: pointer;
    }

    :global(.deepmap-popup-media-arrow.prev) { left: 8px; }
    :global(.deepmap-popup-media-arrow.next) { right: 8px; }

    :global(.deepmap-popup-media-counter) {
        position: absolute;
        right: 9px;
        bottom: 8px;
        z-index: 4;
        padding: 3px 6px;
        border-radius: 999px;
        background: rgba(8,8,10,.72);
        color: #f1f1f3;
        font-size: .62rem;
        font-weight: 800;
    }

    :global(.deepmap-popup-body) {
        padding: 15px 16px 17px;
    }

    :global(.deepmap-popup-category) {
        color: #c8a355;

        font-size: 0.69rem;
        font-weight: 800;

        letter-spacing: 0.8px;
        text-transform: uppercase;

        margin-bottom: 4px;
    }

    :global(.deepmap-popup-title) {
        margin: 0 0 12px;
        padding: 0;

        color: #ffffff;
        font-size: 1.15rem;
        line-height: 1.25;
    }

    :global(.deepmap-popup-info) {
        margin-bottom: 12px;
        padding: 8px 10px;

        background: #111115;
        border-radius: 6px;
        border: 1px solid #292930;
    }

    :global(.deepmap-popup-info-row) {
        display: flex;
        justify-content: space-between;

        gap: 14px;
        padding: 3px 0;

        font-size: 0.78rem;
    }

    :global(.deepmap-popup-info-label) {
        color: #888894;
    }

    :global(.deepmap-popup-info-value) {
        color: #d8d8dd;
        text-align: right;
        font-weight: 600;
    }

    :global(.deepmap-popup-extra-content) {
        display: grid;
        gap: 5px;
        margin-top: 12px;
        padding-top: 10px;
        border-top: 1px solid #292930;
    }

    :global(.deepmap-popup-extra-row) {
        display: grid;
        grid-template-columns: minmax(78px,.42fr) minmax(0,1fr);
        gap: 10px;
        align-items: baseline;
        font-size: .76rem;
    }

    :global(.deepmap-popup-extra-row span) {
        color: #888894;
    }

    :global(.deepmap-popup-extra-row strong) {
        color: #d8d8dd;
        font-weight: 600;
        text-align: right;
        overflow-wrap: anywhere;
    }

    :global(.deepmap-popup-description) {
        margin: 0;
        color: #ababaf;

        font-size: 0.82rem;
        line-height: 1.5;
    }

    :global(.deepmap-popup-footer) {
        display: flex;
        align-items: center;
        gap: 5px;
        margin: 13px -16px -17px;
        padding: 9px 16px;
        border-top: 1px solid #292930;
        background: rgba(10,10,13,.55);
        color: #7f7f88;
        font-size: .68rem;
    }

    :global(.deepmap-popup-footer a) {
        color: #d8b86f;
        font-weight: 800;
        text-decoration: none;
    }

    :global(.deepmap-popup-footer a:hover) {
        text-decoration: underline;
    }


    /* ==========================================
       MARCA D'ÁGUA
       ========================================== */

    :global(.map-watermark) {
        display: flex;
        align-items: center;
        justify-content: center;

        background: rgba(22, 22, 26, 0.5);

        padding: 6px;
        border-radius: 8px;

        border:
            1px solid rgba(200, 163, 85, 0.2);

        backdrop-filter: blur(4px);

        margin-bottom: 12px;
        margin-right: 12px;

        opacity: 0.6;
        pointer-events: none;
    }

    :global(.map-watermark img) {
        height: 28px;
        width: auto;
        display: block;
    }


    /* ==========================================
       MENU MOBILE
       ========================================== */

    .mobile-menu-layer {
        display: none;
    }


    /* ==========================================
       MOBILE
       ========================================== */

    @media (max-width: 768px) {

        .game-subheader {
            padding: 0 8px;
            touch-action: pan-x pan-y;
        }

        .mobile-toggle {
            display: flex;
        }

        .game-brand {
            flex: 1;
            margin-left: 4px;
        }

        .game-title {
            font-size: 1rem;
        }

        .subheader-actions {
            gap: 6px;
        }

        .checklist-status {
            display: none;
        }

        .editor-ui {
            display: none !important;
        }

        .desktop-sidebar {
            display: none;
        }

        .map-wrapper {
            left: 0;
            width: 100%;
        }

        :global(.deepmap-popup) {
            min-width: 210px;
            max-width: calc(100vw - 34px);
        }

        :global(.deepmap-popup-media) {
            width: min(320px, calc(100vw - 34px));
        }


        /* MENU MOBILE INDEPENDENTE — NÃO ALTERAR ESTRUTURA */

        .mobile-menu-layer {
            display: none;

            position: fixed;

            top: calc(var(--deepmap-site-header-height, 62px) + var(--deepmap-game-subheader-height, 52px));
            left: 0;
            right: 0;
            bottom: 0;

            z-index: 20000;
            pointer-events: none;
            touch-action: pan-y;
        }

        .mobile-menu-checkbox:checked ~ .mobile-menu-layer {
            display: block;
            pointer-events: auto;
        }

        .mobile-menu-checkbox:checked ~ .game-subheader .mobile-toggle .menu-icon {
            display: none;
        }

        .mobile-menu-checkbox:checked ~ .game-subheader .mobile-toggle .close-icon {
            display: block;
        }

        .mobile-backdrop {
            display: block;

            position: absolute;

            top: 0;
            left: 0;
            right: 0;
            bottom: 0;

            background: rgba(0, 0, 0, 0.65);
        }

        .mobile-sidebar {
            display: block;

            position: absolute;

            top: 0;
            left: 0;
            bottom: 0;

            width: min(300px, 85vw);

            background: #16161a;
            border-right: 1px solid #2a2a30;

            box-shadow:
                8px 0 30px rgba(0, 0, 0, 0.6);

            box-sizing: border-box;
            z-index: 1;
            overflow-y: auto;
        }

        .mobile-sidebar-header {
            height: 56px;

            display: flex;
            align-items: center;
            justify-content: space-between;

            padding: 0 12px 0 20px;

            border-bottom: 1px solid #2a2a30;
            box-sizing: border-box;
        }

        .mobile-sidebar-header h2 {
            margin: 0;
            font-size: 1.1rem;
            color: #c8a355;
        }

        .mobile-close {
            width: 40px;
            height: 40px;

            display: flex;
            align-items: center;
            justify-content: center;

            padding: 0;

            background: transparent;
            border: 0;

            color: #c8a355;
            font-size: 24px;

            cursor: pointer;
            touch-action: manipulation;
        }

        .mobile-sidebar .sidebar-content {
            height: auto;
            padding: 20px;
        }
    }



    :global(.deepmap-popup-footer) {
        display:flex;
        align-items:flex-end;
        justify-content:space-between;
        gap:10px;
        flex-wrap:wrap;
    }
    :global(.deepmap-popup-attribution) { display:grid; gap:4px; }
    :global(.deepmap-popup-attribution>span) { display:flex; align-items:center; gap:5px; font-size:.68rem; }
    :global(.deepmap-popup-attribution small) { color:#8f8f98; }
    :global(.deepmap-popup-attribution a) { color:#d8b86f; text-decoration:none; font-weight:800; }
    :global(.deepmap-suggest-correction) { padding:6px 8px; border:1px solid #625638; border-radius:6px; background:#17171c; color:#d8b86f; font-size:.68rem; font-weight:800; cursor:pointer; }
    :global(.deepmap-suggest-correction:hover) { border-color:#c8a355; color:#f0d48b; }
    .community-sidebar-actions { display:grid; gap:6px; margin:0 0 12px; padding-bottom:12px; border-bottom:1px solid #2c2c34; }
    .community-sidebar-actions button { padding:8px 9px; border:1px solid #4f4632; border-radius:7px; background:#17171c; color:#d8b86f; font-weight:800; cursor:pointer; text-align:left; }
    .community-sidebar-actions button:first-child { border-color:#c8a355; background:rgba(200,163,85,.1); }
</style>
