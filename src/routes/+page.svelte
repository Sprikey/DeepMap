<script>
	import { onMount } from 'svelte';

	let mapContainer;
	let map;
	let Leaflet;

	let mapImageOverlay = null;


	/* ==========================================
	   IDIOMAS / TRADUÇÕES
	   ========================================== */

	let currentLanguage = 'en';


	const translations = {

		en: {

			/* Interface */

			filters: 'Filters',

			locations: 'Locations',

			collectibles: 'Collectibles',

			sites_of_grace: 'Sites of Grace',

			dungeons_caverns:
				'Dungeons & Caverns',

			bosses: 'Bosses',

			weapons_equipment:
				'Weapons & Equipment',

			stonesword_keys:
				'Stonesword Keys',

			talismans:
				'Talismans',

			checklist:
				'Checklist',


			/* Categorias */

			site_of_grace:
				'Site of Grace',


			/* Regiões */

			limgrave:
				'Limgrave',


			/* Locais */

			church_of_elleh:
				'Church of Elleh',

			church_of_elleh_description:
				'A ruined church located in Limgrave. It contains a Site of Grace and is one of the first notable locations encountered when exploring the region.',


			/* Labels opcionais do popup */

			region:
				'Region',

			npcs:
				'NPCs',

			items:
				'Items',

			quests:
				'Quests',

			notes:
				'Notes',


			/* Editor */

			editor:
				'⚙️ EDITOR',

			editor_active:
				'🛠️ EDITOR ACTIVE',

			coordinate_editor:
				'🛠️ COORDINATE EDITOR',

			editor_instruction:
				'Click a point on the map to get its coordinates.',

			editor_status:
				'EDITOR MODE ACTIVE — Click on the map',

			ready_for_leaflet:
				'Ready for Leaflet:',

			copy:
				'📋 COPY',

			copied:
				'✓ Copied!',


			/* Acessibilidade */

			open_menu:
				'Open Menu',

			close_menu:
				'Close Menu',

			language:
				'Language'
		},


		pt: {

			/* Interface */

			filters:
				'Filtros',

			locations:
				'Locais',

			collectibles:
				'Colecionáveis',

			sites_of_grace:
				'Locais de Graça',

			dungeons_caverns:
				'Masmorras e Cavernas',

			bosses:
				'Chefes',

			weapons_equipment:
				'Armas e Equipamento',

			stonesword_keys:
				'Chaves de Espada de Pedra',

			talismans:
				'Talismãs',

			checklist:
				'Progresso',


			/* Categorias */

			site_of_grace:
				'Local de Graça',


			/* Regiões */

			limgrave:
				'Limgrave',


			/* Locais */

			church_of_elleh:
				'Igreja de Elleh',

			church_of_elleh_description:
				'Uma igreja em ruínas situada em Limgrave. Contém um Local de Graça e é um dos primeiros locais importantes encontrados ao explorar a região.',


			/* Labels opcionais do popup */

			region:
				'Região',

			npcs:
				'NPCs',

			items:
				'Itens',

			quests:
				'Missões',

			notes:
				'Notas',


			/* Editor */

			editor:
				'⚙️ EDITOR',

			editor_active:
				'🛠️ EDITOR ATIVO',

			coordinate_editor:
				'🛠️ EDITOR DE COORDENADAS',

			editor_instruction:
				'Clica num ponto do mapa para obter as coordenadas.',

			editor_status:
				'MODO EDITOR ATIVO — Clica no mapa',

			ready_for_leaflet:
				'Pronto para Leaflet:',

			copy:
				'📋 COPIAR',

			copied:
				'✓ Copiado!',


			/* Acessibilidade */

			open_menu:
				'Abrir Menu',

			close_menu:
				'Fechar Menu',

			language:
				'Idioma'
		}
	};


	/* Obtém uma tradução */

	function t(key) {

		return (
			translations[currentLanguage]?.[key] ??
			translations.en?.[key] ??
			key
		);
	}


	/* Troca o idioma */

	function changeLanguage(event) {

		currentLanguage =
			event.currentTarget.value;


		/*
			Os textos normais da interface são
			atualizados automaticamente pelo Svelte.

			Os marcadores e popups Leaflet precisam
			de ser reconstruídos.
		*/

		renderLocationMarkers();


		/*
			O editor utiliza alguns elementos
			controlados diretamente por JavaScript.
		*/

		updateEditorInterface();
	}



	/* ==========================================
	   FILTROS
	   ========================================== */

	/*
		Estado central dos filtros.

		Desktop e mobile utilizam exatamente
		estes mesmos valores.

		Por isso, alterar um checkbox num lado
		atualiza automaticamente o outro.
	*/

	let categoryVisibility = {

		site_of_grace: true,

		dungeon: true,

		boss: true,

		weapon_equipment: true,

		stonesword_key: true,

		talisman: true
	};


	/*
		Ativa ou desativa uma categoria.
	*/

	function setCategoryVisibility(
		categoryId,
		visible
	) {

		categoryVisibility = {

			...categoryVisibility,

			[categoryId]: visible
		};


		/*
			Recriamos os marcadores respeitando
			os filtros atuais.
		*/

		renderLocationMarkers();
	}



	/* ==========================================
	   MAPAS / CAMADAS
	   ========================================== */

	/*
		Cada mapa/camada é independente.

		Hoje usamos apenas "surface".

		Mais tarde podemos acrescentar:
		- underground
		- DLC
		- interiores
		- etc.

		As coordenadas dos marcadores pertencem
		sempre à layer definida em "mapLayer".
	*/

	const mapDefinitions = {

		surface: {

			id:
				'surface',

			image:
				'/mapa-elden-ring.jpg',

			width:
				8000,

			height:
				8000
		},


		underground: {

			id:
				'underground',

			/*
				Quando tivermos o mapa
				subterrâneo:

				image:
				'/maps/elden-ring-underground.jpg'
			*/

			image:
				null,

			width:
				8000,

			height:
				8000
		},


		dlc: {

			id:
				'dlc',

			/*
				Preparado para uma possível
				layer/mapa DLC.
			*/

			image:
				null,

			width:
				8000,

			height:
				8000
		}
	};


	let activeMapLayer =
		'surface';


	let markerLayerGroups =
		{};



	/* Cria bounds para uma determinada layer */

	function getMapBounds(
		mapDefinition
	) {

		return [

			[0, 0],

			[
				mapDefinition.height,
				mapDefinition.width
			]
		];
	}



	/*
		Cria os grupos Leaflet.

		Cada layer tem o seu próprio
		grupo de marcadores.
	*/

	function setupMarkerLayers() {

		for (
			const layerId of
			Object.keys(mapDefinitions)
		) {

			markerLayerGroups[layerId] =
				Leaflet.layerGroup();
		}


		/*
			Apenas a layer ativa
			é adicionada ao mapa.
		*/

		markerLayerGroups[
			activeMapLayer
		].addTo(map);
	}



	/*
		Função preparada para trocar
		de mapa/camada.

		Por enquanto não existe botão
		na interface porque só temos
		a superfície.

		Mais tarde podemos chamar:

		setActiveMapLayer('underground');
	*/

	function setActiveMapLayer(
		layerId
	) {

		if (!map) return;


		const definition =
			mapDefinitions[layerId];


		if (!definition) return;


		/* Remove os grupos atualmente visíveis */

		for (
			const group of
			Object.values(markerLayerGroups)
		) {

			if (
				map.hasLayer(group)
			) {

				map.removeLayer(group);
			}
		}


		activeMapLayer =
			layerId;


		/* Liga apenas os marcadores da layer selecionada */

		const activeGroup =
			markerLayerGroups[
				activeMapLayer
			];


		if (activeGroup) {

			activeGroup.addTo(map);
		}


		/*
			Se a layer tiver uma imagem própria,
			trocamos também o mapa visual.
		*/

		if (definition.image) {

			const bounds =
				getMapBounds(
					definition
				);


			if (mapImageOverlay) {

				map.removeLayer(
					mapImageOverlay
				);
			}


			mapImageOverlay =
				Leaflet.imageOverlay(
					definition.image,
					bounds
				).addTo(map);


			mapImageOverlay.bringToBack();


			map.setMaxBounds(
				bounds
			);


			map.fitBounds(
				bounds
			);
		}
	}



	/* ==========================================
	   DADOS DOS LOCAIS
	   ========================================== */

	/*
		IMPORTANTE:

		Os dados estruturais não dependem
		do idioma.

		IDs, categorias, coordenadas e layers
		continuam sempre iguais.

		Os textos usam keys de tradução.
	*/

	const locations = [

		{

			id:
				'church-of-elleh',


			/* Layer a que pertence este marcador */

			mapLayer:
				'surface',


			/*
				Categoria interna.

				É esta propriedade que permite
				aos filtros saberem quais
				marcadores mostrar/esconder.
			*/

			categoryId:
				'site_of_grace',


			/* Traduções */

			nameKey:
				'church_of_elleh',

			descriptionKey:
				'church_of_elleh_description',

			categoryKey:
				'site_of_grace',

			regionKey:
				'limgrave',


			/* Coordenadas Leaflet = [Y, X] */

			coordinates:
				[2300, 3204],


			/* Ícone mostrado no mapa */

			icon:
				'/icons/site-of-grace.png',


			/* Imagem mostrada dentro do popup */

			image:
				'/locations/church-of-elleh.jpg',



			/* =====================================
			   CAMPOS OPCIONAIS
			   =====================================

			   Se estiverem vazios ou não existirem,
			   não aparecem no popup.
			*/

			npcs:
				[],

			items:
				[],

			quests:
				[],

			notesKey:
				null,



			/* =====================================
			   PREMIUM — PREPARADO PARA SUPABASE
			   =====================================

			   Isto NÃO contém os dados premium.

			   Apenas indica que no futuro este local
			   poderá ter estas secções premium.

			   O conteúdo real será carregado através
			   do Supabase depois de confirmar que
			   o utilizador tem acesso premium.
			*/

			premium: {

				provider:
					'supabase',

				sections: [

					'npcs',

					'items',

					'quests',

					'notes'
				]
			}
		}
	];



	/* ==========================================
	   POPUPS
	   ========================================== */


	/*
		Evita que texto introduzido futuramente
		possa inserir HTML inesperado no popup.
	*/

	function escapeHtml(value) {

		return String(value)

			.replaceAll(
				'&',
				'&amp;'
			)

			.replaceAll(
				'<',
				'&lt;'
			)

			.replaceAll(
				'>',
				'&gt;'
			)

			.replaceAll(
				'"',
				'&quot;'
			)

			.replaceAll(
				"'",
				'&#039;'
			);
	}



	/*
		Traduz uma lista de keys.

		Exemplo futuro:

		npcs: ['merchant_kale']
	*/

	function translateList(list) {

		if (
			!list ||
			!list.length
		) {

			return '';
		}


		return list

			.map(
				(item) => t(item)
			)

			.join(', ');
	}



	/*
		Cria uma linha opcional
		do popup.
	*/

	function createPopupInfoRow(
		labelKey,
		value
	) {

		if (!value) return '';


		return `
			<div class="deepmap-popup-info-row">

				<span class="deepmap-popup-info-label">

					${escapeHtml(
						t(labelKey)
					)}

				</span>


				<span class="deepmap-popup-info-value">

					${escapeHtml(value)}

				</span>

			</div>
		`;
	}



	/*
		Constrói todo o popup
		de uma localização.
	*/

	function buildLocationPopup(
		location
	) {

		let optionalInformation =
			'';



		/* Região */

		if (
			location.regionKey
		) {

			optionalInformation +=
				createPopupInfoRow(

					'region',

					t(
						location.regionKey
					)
				);
		}



		/* NPCs */

		if (
			location.npcs?.length
		) {

			optionalInformation +=
				createPopupInfoRow(

					'npcs',

					translateList(
						location.npcs
					)
				);
		}



		/* Itens */

		if (
			location.items?.length
		) {

			optionalInformation +=
				createPopupInfoRow(

					'items',

					translateList(
						location.items
					)
				);
		}



		/* Quests */

		if (
			location.quests?.length
		) {

			optionalInformation +=
				createPopupInfoRow(

					'quests',

					translateList(
						location.quests
					)
				);
		}



		/* Notas */

		if (
			location.notesKey
		) {

			optionalInformation +=
				createPopupInfoRow(

					'notes',

					t(
						location.notesKey
					)
				);
		}



		/* Imagem */

		const imageHTML =
			location.image

				? `
					<div class="deepmap-popup-image-wrapper">

						<img
							src="${escapeHtml(
								location.image
							)}"

							alt="${escapeHtml(
								t(
									location.nameKey
								)
							)}"

							class="deepmap-popup-image"

							onerror="this.parentElement.style.display='none'"
						/>

					</div>
				`

				: '';



		return `

			<div class="deepmap-popup">

				${imageHTML}


				<div class="deepmap-popup-body">


					<div class="deepmap-popup-category">

						${escapeHtml(
							t(
								location.categoryKey
							)
						)}

					</div>


					<h3 class="deepmap-popup-title">

						${escapeHtml(
							t(
								location.nameKey
							)
						)}

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
						location.descriptionKey

							? `
								<p class="deepmap-popup-description">

									${escapeHtml(
										t(
											location.descriptionKey
										)
									)}

								</p>
							`

							: ''
					}


				</div>

			</div>
		`;
	}



	/* ==========================================
	   MARCADORES
	   ========================================== */


	function createLocationIcon(
		location
	) {

		return Leaflet.icon({

			iconUrl:
				location.icon,


			/*
				O teu ícone atual é mais alto
				do que largo.

				Podemos ajustar depois
				se quiseres.
			*/

			iconSize:
				[34, 46],

			iconAnchor:
				[17, 46],

			popupAnchor:
				[0, -42],

			className:
				'deepmap-marker-icon'
		});
	}



	/*
		Cria/recria os marcadores.

		É utilizado quando:
		- mudamos o idioma
		- ativamos/desativamos filtros
	*/

	function renderLocationMarkers() {

		if (
			!map ||
			!Leaflet ||
			!Object.keys(
				markerLayerGroups
			).length
		) {

			return;
		}



		/* Limpa os grupos */

		for (
			const group of
			Object.values(
				markerLayerGroups
			)
		) {

			group.clearLayers();
		}



		/* Cria os marcadores */

		for (
			const location of
			locations
		) {


			/*
				Se a categoria estiver desligada
				no filtro, não criamos o marcador.
			*/

			if (
				categoryVisibility[
					location.categoryId
				] === false
			) {

				continue;
			}



			const group =
				markerLayerGroups[
					location.mapLayer
				];


			if (!group) continue;



			const marker =
				Leaflet.marker(

					location.coordinates,

					{

						icon:
							createLocationIcon(
								location
							),

						title:
							t(
								location.nameKey
							)
					}
				);



			/* Popup */

			marker.bindPopup(

				buildLocationPopup(
					location
				),

				{

					maxWidth:
						330,

					minWidth:
						280,

					className:
						'deepmap-leaflet-popup'
				}
			);



			/*
				Tooltip ao passar o rato
				por cima do marcador.
			*/

			marker.bindTooltip(

				t(
					location.nameKey
				),

				{

					direction:
						'top',

					offset:
						[0, -38]
				}
			);



			marker.addTo(
				group
			);
		}
	}



	/* ==========================================
	   EDITOR DE COORDENADAS
	   ========================================== */

	let editorMode =
		false;


	let editorMarker =
		null;


	let editorX =
		null;


	let editorY =
		null;



	/*
		Atualiza visualmente toda
		a interface do editor.

		A interface fica sempre
		presente no HTML.
	*/

	function updateEditorInterface() {

		if (
			typeof document ===
			'undefined'
		) {

			return;
		}



		const editorButton =
			document.getElementById(
				'editor-toggle'
			);


		const editorStatus =
			document.getElementById(
				'editor-status'
			);


		const coordinatePanel =
			document.getElementById(
				'coordinate-panel'
			);


		const xValue =
			document.getElementById(
				'editor-x'
			);


		const yValue =
			document.getElementById(
				'editor-y'
			);


		const arrayValue =
			document.getElementById(
				'editor-array'
			);


		const instruction =
			document.getElementById(
				'editor-instruction'
			);


		const coordinatesContent =
			document.getElementById(
				'coordinates-content'
			);


		const copyButton =
			document.getElementById(
				'copy-coordinates'
			);


		const copyStatus =
			document.getElementById(
				'copy-status'
			);



		/* Editor desligado */

		if (!editorMode) {

			if (editorButton) {

				editorButton.textContent =
					t('editor');


				editorButton.classList.remove(
					'active'
				);
			}


			if (editorStatus) {

				editorStatus.style.display =
					'none';
			}


			if (coordinatePanel) {

				coordinatePanel.style.display =
					'none';
			}


			return;
		}



		/* Editor ligado */

		if (editorButton) {

			editorButton.textContent =
				t(
					'editor_active'
				);


			editorButton.classList.add(
				'active'
			);
		}


		if (editorStatus) {

			editorStatus.style.display =
				'flex';
		}


		if (coordinatePanel) {

			coordinatePanel.style.display =
				'block';
		}



		/* Ainda não existe ponto */

		if (
			editorX === null ||
			editorY === null
		) {

			if (instruction) {

				instruction.style.display =
					'block';
			}


			if (coordinatesContent) {

				coordinatesContent.style.display =
					'none';
			}


			if (copyButton) {

				copyButton.disabled =
					true;
			}


			if (copyStatus) {

				copyStatus.textContent =
					'';
			}


			return;
		}



		/* Temos coordenadas */

		if (instruction) {

			instruction.style.display =
				'none';
		}


		if (coordinatesContent) {

			coordinatesContent.style.display =
				'block';
		}


		if (xValue) {

			xValue.textContent =
				editorX;
		}


		if (yValue) {

			yValue.textContent =
				editorY;
		}



		/*
			Leaflet utiliza:

			[Y, X]
		*/

		if (arrayValue) {

			arrayValue.textContent =
				`[${editorY}, ${editorX}]`;
		}


		if (copyButton) {

			copyButton.disabled =
				false;
		}


		if (copyStatus) {

			copyStatus.textContent =
				'';
		}
	}



	/* Liga / desliga o editor */

	function toggleEditor() {

		editorMode =
			!editorMode;



		if (!editorMode) {

			if (
				editorMarker &&
				map
			) {

				map.removeLayer(
					editorMarker
				);
			}


			editorMarker =
				null;


			editorX =
				null;


			editorY =
				null;
		}



		updateEditorInterface();
	}



	/* Copiar coordenadas */

	async function copyCoordinates() {

		if (
			editorX === null ||
			editorY === null
		) {

			return;
		}



		const coordinates =
			`[${editorY}, ${editorX}]`;


		const copyStatus =
			document.getElementById(
				'copy-status'
			);



		try {

			await navigator.clipboard.writeText(
				coordinates
			);


			if (copyStatus) {

				copyStatus.textContent =
					t('copied');
			}

		} catch (error) {


			const textarea =
				document.createElement(
					'textarea'
				);


			textarea.value =
				coordinates;


			textarea.style.position =
				'fixed';


			textarea.style.opacity =
				'0';


			document.body.appendChild(
				textarea
			);


			textarea.select();


			document.execCommand(
				'copy'
			);


			document.body.removeChild(
				textarea
			);


			if (copyStatus) {

				copyStatus.textContent =
					t('copied');
			}
		}
	}



	/* ==========================================
	   INICIALIZAÇÃO DO MAPA
	   ========================================== */

	onMount(async () => {


		const L =
			await import(
				'leaflet'
			);


		await import(
			'leaflet/dist/leaflet.css'
		);


		Leaflet =
			L;



		const surfaceDefinition =
			mapDefinitions.surface;



		const bounds =
			getMapBounds(
				surfaceDefinition
			);



		map =
			L.map(

				mapContainer,

				{

					crs:
						L.CRS.Simple,


					maxBounds:
						bounds,


					maxBoundsViscosity:
						0.8,


					attributionControl:
						false,


					minZoom:
						-3,


					maxZoom:
						2,


					zoomSnap:
						0.25
				}
			);



		/* Imagem principal */

		mapImageOverlay =
			L.imageOverlay(

				surfaceDefinition.image,

				bounds

			).addTo(map);



		/* ==========================================
		   MARCA D'ÁGUA
		   ========================================== */

		const LogoWatermark =
			L.Control.extend({

				options: {

					position:
						'bottomright'
				},


				onAdd:
					function () {

						const div =
							L.DomUtil.create(

								'div',

								'map-watermark'
							);


						div.innerHTML = `
							<img
								src="/logo.png"
								alt="DeepMap Logo"
							/>
						`;


						return div;
					}
			});



		map.addControl(
			new LogoWatermark()
		);



		/* ==========================================
		   LAYERS DOS MARCADORES
		   ========================================== */

		setupMarkerLayers();


		renderLocationMarkers();



		/* ==========================================
		   CLIQUE NO MAPA — EDITOR
		   ========================================== */

		map.on(
			'click',

			(e) => {


				if (
					!editorMode
				) {

					return;
				}



				/*
					Leaflet:

					lat = Y
					lng = X
				*/

				const x =
					Math.round(
						e.latlng.lng
					);


				const y =
					Math.round(
						e.latlng.lat
					);



				editorX =
					x;


				editorY =
					y;



				if (
					editorMarker
				) {

					map.removeLayer(
						editorMarker
					);
				}



				editorMarker =
					Leaflet.circleMarker(

						[y, x],

						{

							radius:
								9,


							color:
								'#ff9f1c',


							weight:
								3,


							fillColor:
								'#ff9f1c',


							fillOpacity:
								0.45
						}

					).addTo(map);



				updateEditorInterface();
			}
		);



		mapImageOverlay.on(
			'load',

			() => {

				map.fitBounds(
					bounds
				);
			}
		);



		map.fitBounds(
			bounds
		);



		setTimeout(

			() => {

				if (map) {

					map.invalidateSize();
				}
			},

			250
		);
	});
</script>



<div class="app-container">


	<!-- ================================================= -->
	<!-- CONTROLO DO MENU MOBILE -->
	<!-- Checkbox invisível: o CSS controla abrir/fechar -->
	<!-- ================================================= -->

	<input
		type="checkbox"
		id="mobile-menu-toggle"
		class="mobile-menu-checkbox"
	/>



	<!-- ================================================= -->
	<!-- HEADER -->
	<!-- ================================================= -->

	<header class="header">


		<!-- Botão do menu apenas para mobile -->

		<label
			for="mobile-menu-toggle"
			class="mobile-toggle"
			aria-label={t('open_menu')}
		>

			<span class="menu-icon">
				☰
			</span>


			<span class="close-icon">
				✕
			</span>

		</label>



		<div class="brand">


			<img
				src="/logo.png"
				alt="DeepMap"
				class="logo-img"
			/>


			<span class="game-title">

				Elden Ring

			</span>


			<span class="version-tag">

				v1.0.25

			</span>

		</div>



		<div class="header-actions">


			<!-- Seletor de idioma -->

			<select
				class="language-selector"
				value={currentLanguage}
				onchange={changeLanguage}
				aria-label={t('language')}
			>

				<option value="en">
					EN
				</option>


				<option value="pt">
					PT
				</option>

			</select>



			<div class="checklist-status">

				{t('checklist')}

				<span>
					(0%)
				</span>

			</div>

		</div>

	</header>



	<!-- ================================================= -->
	<!-- EDITOR DE COORDENADAS -->
	<!-- Apenas utilizado no PC -->
	<!-- ================================================= -->

	<div class="editor-ui">


		<button
			id="editor-toggle"
			class="editor-toggle"
			onclick={toggleEditor}
		>

			{t('editor')}

		</button>



		<div
			id="coordinate-panel"
			class="coordinate-panel"
		>


			<div class="coordinate-title">

				{t('coordinate_editor')}

			</div>



			<div
				id="editor-instruction"
				class="editor-instruction"
			>

				{t('editor_instruction')}

			</div>



			<div
				id="coordinates-content"
				class="coordinates-content"
			>


				<div class="coordinate-row">

					<span>
						X:
					</span>

					<strong id="editor-x">
						—
					</strong>

				</div>



				<div class="coordinate-row">

					<span>
						Y:
					</span>

					<strong id="editor-y">
						—
					</strong>

				</div>



				<div class="coordinate-divider">
				</div>



				<div class="coordinate-label">

					{t('ready_for_leaflet')}

				</div>



				<div
					id="editor-array"
					class="coordinate-array"
				>

					[Y, X]

				</div>



				<button
					id="copy-coordinates"
					class="copy-button"
					onclick={copyCoordinates}
					disabled
				>

					{t('copy')}

				</button>



				<div
					id="copy-status"
					class="copy-status"
				>
				</div>

			</div>

		</div>

	</div>



	<!-- Indicador do modo editor -->

	<div
		id="editor-status"
		class="editor-status"
	>

		<span class="editor-status-dot">
		</span>


		{t('editor_status')}

	</div>



	<!-- ================================================= -->
	<!-- CONTEÚDO PRINCIPAL -->
	<!-- ================================================= -->

	<div class="body-container">


		<!-- Sidebar Desktop -->

		<aside class="desktop-sidebar">


			<div class="sidebar-content">


				<h2>
					{t('filters')}
				</h2>



				<div class="filter-group">


					<h3>
						{t('locations')}
					</h3>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.site_of_grace
							}

							onchange={(event) =>
								setCategoryVisibility(
									'site_of_grace',
									event.currentTarget.checked
								)
							}
						/>

						{t('sites_of_grace')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.dungeon
							}

							onchange={(event) =>
								setCategoryVisibility(
									'dungeon',
									event.currentTarget.checked
								)
							}
						/>

						{t('dungeons_caverns')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.boss
							}

							onchange={(event) =>
								setCategoryVisibility(
									'boss',
									event.currentTarget.checked
								)
							}
						/>

						{t('bosses')}

					</label>

				</div>



				<div class="filter-group">


					<h3>
						{t('collectibles')}
					</h3>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.weapon_equipment
							}

							onchange={(event) =>
								setCategoryVisibility(
									'weapon_equipment',
									event.currentTarget.checked
								)
							}
						/>

						{t('weapons_equipment')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.stonesword_key
							}

							onchange={(event) =>
								setCategoryVisibility(
									'stonesword_key',
									event.currentTarget.checked
								)
							}
						/>

						{t('stonesword_keys')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.talisman
							}

							onchange={(event) =>
								setCategoryVisibility(
									'talisman',
									event.currentTarget.checked
								)
							}
						/>

						{t('talismans')}

					</label>

				</div>

			</div>

		</aside>



		<!-- Contentor do Mapa Leaflet -->

		<main class="map-wrapper">

			<div
				bind:this={mapContainer}
				class="map-element"
			>
			</div>

		</main>

	</div>



	<!-- ================================================= -->
	<!-- MENU MOBILE -->
	<!-- É controlado pelo checkbox através de CSS -->
	<!-- ================================================= -->

	<div class="mobile-menu-layer">


		<label
			for="mobile-menu-toggle"
			class="mobile-backdrop"
			aria-label={t('close_menu')}
		>
		</label>



		<aside class="mobile-sidebar">


			<div class="mobile-sidebar-header">


				<h2>
					{t('filters')}
				</h2>



				<label
					for="mobile-menu-toggle"
					class="mobile-close"
					aria-label={t('close_menu')}
				>

					✕

				</label>

			</div>



			<div class="sidebar-content">


				<div class="filter-group">


					<h3>
						{t('locations')}
					</h3>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.site_of_grace
							}

							onchange={(event) =>
								setCategoryVisibility(
									'site_of_grace',
									event.currentTarget.checked
								)
							}
						/>

						{t('sites_of_grace')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.dungeon
							}

							onchange={(event) =>
								setCategoryVisibility(
									'dungeon',
									event.currentTarget.checked
								)
							}
						/>

						{t('dungeons_caverns')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.boss
							}

							onchange={(event) =>
								setCategoryVisibility(
									'boss',
									event.currentTarget.checked
								)
							}
						/>

						{t('bosses')}

					</label>

				</div>



				<div class="filter-group">


					<h3>
						{t('collectibles')}
					</h3>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.weapon_equipment
							}

							onchange={(event) =>
								setCategoryVisibility(
									'weapon_equipment',
									event.currentTarget.checked
								)
							}
						/>

						{t('weapons_equipment')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.stonesword_key
							}

							onchange={(event) =>
								setCategoryVisibility(
									'stonesword_key',
									event.currentTarget.checked
								)
							}
						/>

						{t('stonesword_keys')}

					</label>



					<label>

						<input
							type="checkbox"

							checked={
								categoryVisibility.talisman
							}

							onchange={(event) =>
								setCategoryVisibility(
									'talisman',
									event.currentTarget.checked
								)
							}
						/>

						{t('talismans')}

					</label>

				</div>

			</div>

		</aside>

	</div>

</div>



<style>

	:global(html),
	:global(body) {

		margin: 0;

		padding: 0;

		width: 100%;

		height: 100%;

		overflow: hidden;

		background-color: #0b0b0e;

		font-family:
			'Segoe UI',
			Roboto,
			Helvetica,
			Arial,
			sans-serif;

		color: #e0e0e0;
	}



	.app-container {

		width: 100vw;

		height: 100vh;

		height: 100dvh;

		overflow: hidden;

		background: #0b0b0e;
	}



	/* ==========================================
	   HEADER
	   ========================================== */

	.header {

		position: fixed;

		top: 0;

		left: 0;

		right: 0;

		height: 56px;

		background: #16161a;

		border-bottom:
			1px solid #2a2a30;

		display: flex;

		align-items: center;

		justify-content:
			space-between;

		padding: 0 16px;

		box-sizing: border-box;

		z-index: 10000;
	}



	.brand {

		display: flex;

		align-items: center;

		gap: 12px;
	}



	.logo-img {

		height: 32px;

		width: auto;
	}



	.game-title {

		font-size: 1.2rem;

		font-weight: 700;

		color: #c8a355;

		letter-spacing: 1px;
	}



	.version-tag {

		font-size: 0.75rem;

		color: #888899;

		background: #22222a;

		padding: 2px 6px;

		border-radius: 4px;

		border:
			1px solid #333340;
	}



	.header-actions {

		display: flex;

		align-items: center;

		gap: 12px;
	}



	.language-selector {

		background: #22222a;

		border:
			1px solid #3a3a45;

		border-radius: 5px;

		color: #c8a355;

		padding: 5px 7px;

		font-weight: 700;

		cursor: pointer;

		outline: none;
	}



	.language-selector:hover {

		border-color: #c8a355;
	}



	.checklist-status {

		font-size: 0.9rem;

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
	   EDITOR DE COORDENADAS
	   ========================================== */

	.editor-ui {

		position: fixed !important;

		top: 68px !important;

		right: 16px !important;

		width: 280px;

		z-index: 999999 !important;

		pointer-events: none;
	}



	.editor-toggle {

		display: block;

		margin-left: auto;

		padding: 10px 16px;

		background: #16161a;

		border:
			1px solid #c8a355;

		border-radius: 6px;

		color: #c8a355;

		font-size: 0.78rem;

		font-weight: 700;

		letter-spacing: 0.5px;

		cursor: pointer;

		box-shadow:
			0 4px 15px
			rgba(0, 0, 0, 0.4);

		pointer-events: auto;

		transition:
			background 0.2s,
			color 0.2s,
			box-shadow 0.2s;
	}



	.editor-toggle:hover {

		background: #22222a;
	}



	.editor-toggle.active {

		background: #c8a355;

		color: #111116;

		box-shadow:
			0 0 0 2px
				rgba(200, 163, 85, 0.15),
			0 5px 20px
				rgba(0, 0, 0, 0.5);
	}



	.coordinate-panel {

		display: none;

		margin-top: 10px;

		background:
			rgba(22, 22, 26, 0.97);

		border:
			1px solid #c8a355;

		border-radius: 8px;

		padding: 16px;

		box-sizing: border-box;

		box-shadow:
			0 8px 30px
			rgba(0, 0, 0, 0.65);

		backdrop-filter:
			blur(8px);

		pointer-events: auto;
	}



	.coordinate-title {

		color: #c8a355;

		font-size: 0.8rem;

		font-weight: 700;

		letter-spacing: 0.6px;

		margin-bottom: 14px;

		padding-bottom: 10px;

		border-bottom:
			1px solid #2a2a30;
	}



	.editor-instruction {

		font-size: 0.85rem;

		color: #b0b0b8;

		line-height: 1.5;
	}



	.coordinates-content {

		display: none;
	}



	.coordinate-row {

		display: flex;

		align-items: center;

		justify-content:
			space-between;

		margin-bottom: 8px;

		font-size: 0.95rem;
	}



	.coordinate-row span {

		color: #9999a5;
	}



	.coordinate-row strong {

		color: #ffffff;

		font-size: 1rem;
	}



	.coordinate-divider {

		height: 1px;

		background: #2a2a30;

		margin: 14px 0;
	}



	.coordinate-label {

		color: #888899;

		font-size: 0.75rem;

		text-transform:
			uppercase;

		letter-spacing: 0.5px;

		margin-bottom: 7px;
	}



	.coordinate-array {

		background: #0b0b0e;

		border:
			1px solid #333340;

		border-radius: 5px;

		padding: 10px;

		margin-bottom: 10px;

		text-align: center;

		font-family: monospace;

		font-size: 1rem;

		font-weight: 700;

		color: #ffb640;

		user-select: all;
	}



	.copy-button {

		width: 100%;

		padding: 9px;

		background: #c8a355;

		border: 0;

		border-radius: 5px;

		color: #111116;

		font-size: 0.78rem;

		font-weight: 800;

		cursor: pointer;
	}



	.copy-button:disabled {

		opacity: 0.35;

		cursor: not-allowed;
	}



	.copy-status {

		min-height: 18px;

		margin-top: 7px;

		color: #7edc98;

		font-size: 0.75rem;

		font-weight: 600;

		text-align: center;
	}



	.editor-status {

		display: none;

		position: fixed !important;

		top: 68px !important;

		left: 50% !important;

		transform:
			translateX(-50%);

		align-items: center;

		gap: 8px;

		padding: 8px 14px;

		background:
			rgba(22, 22, 26, 0.96);

		border:
			1px solid #ff9f1c;

		border-radius: 6px;

		color: #ffb340;

		font-size: 0.76rem;

		font-weight: 800;

		letter-spacing: 0.4px;

		box-shadow:
			0 5px 20px
			rgba(0, 0, 0, 0.55);

		z-index:
			999999 !important;

		pointer-events: none;
	}



	.editor-status-dot {

		width: 8px;

		height: 8px;

		border-radius: 50%;

		background: #ff9f1c;

		box-shadow:
			0 0 8px
			rgba(255, 159, 28, 0.8);
	}



	/* ==========================================
	   BODY / MAPA
	   ========================================== */

	.body-container {

		position: fixed;

		top: 56px;

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

		top: 56px;

		left: 0;

		bottom: 0;

		width: 300px;

		background: #16161a;

		border-right:
			1px solid #2a2a30;

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

		border-bottom:
			1px solid #2a2a30;

		padding-bottom: 8px;
	}



	.filter-group {

		margin-bottom: 20px;
	}



	.filter-group h3 {

		font-size: 0.9rem;

		color: #888;

		text-transform:
			uppercase;

		letter-spacing: 0.5px;

		margin-bottom: 10px;
	}



	.filter-group label {

		display: flex;

		align-items: center;

		gap: 10px;

		margin-bottom: 8px;

		font-size: 0.95rem;

		cursor: pointer;
	}



	.filter-group input[type='checkbox'] {

		accent-color: #c8a355;

		width: 16px;

		height: 16px;
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
	   ÍCONES DOS MARCADORES
	   ========================================== */

	:global(.deepmap-marker-icon) {

		filter:
			drop-shadow(
				0 3px 4px
				rgba(0, 0, 0, 0.7)
			);

		transition:
			transform 0.15s ease;
	}



	:global(.deepmap-marker-icon:hover) {

		transform:
			scale(1.12);
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
			1px solid
			rgba(200, 163, 85, 0.45);

		overflow: hidden;

		box-shadow:
			0 12px 35px
			rgba(0, 0, 0, 0.7);
	}



	:global(.deepmap-leaflet-popup .leaflet-popup-content) {

		margin: 0;

		width: auto !important;
	}



	:global(.deepmap-leaflet-popup .leaflet-popup-tip) {

		background: #16161a;
	}



	:global(.deepmap-leaflet-popup .leaflet-popup-close-button) {

		color:
			#ffffff !important;

		background:
			rgba(0, 0, 0, 0.55) !important;

		width:
			28px !important;

		height:
			28px !important;

		line-height:
			27px !important;

		border-radius: 50%;

		top:
			7px !important;

		right:
			7px !important;

		z-index: 5;

		font-size:
			18px !important;
	}



	:global(.deepmap-popup) {

		width: 310px;

		max-width: 100%;
	}



	:global(.deepmap-popup-image-wrapper) {

		width: 100%;

		height: 165px;

		overflow: hidden;

		background: #0b0b0e;
	}



	:global(.deepmap-popup-image) {

		width: 100%;

		height: 100%;

		display: block;

		object-fit: cover;
	}



	:global(.deepmap-popup-body) {

		padding:
			15px 16px 17px;
	}



	:global(.deepmap-popup-category) {

		color: #c8a355;

		font-size: 0.69rem;

		font-weight: 800;

		letter-spacing: 0.8px;

		text-transform:
			uppercase;

		margin-bottom: 4px;
	}



	:global(.deepmap-popup-title) {

		margin:
			0 0 12px;

		padding: 0;

		color: #ffffff;

		font-size: 1.15rem;

		line-height: 1.25;
	}



	:global(.deepmap-popup-info) {

		margin-bottom: 12px;

		padding:
			8px 10px;

		background: #111115;

		border-radius: 6px;

		border:
			1px solid #292930;
	}



	:global(.deepmap-popup-info-row) {

		display: flex;

		justify-content:
			space-between;

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



	:global(.deepmap-popup-description) {

		margin: 0;

		color: #ababaf;

		font-size: 0.82rem;

		line-height: 1.5;
	}



	/* Marca d'água no canto inferior direito (Apenas logo e bem transparente) */

	:global(.map-watermark) {

		display: flex;

		align-items: center;

		justify-content: center;

		background:
			rgba(22, 22, 26, 0.5);

		padding: 6px;

		border-radius: 8px;

		border:
			1px solid
			rgba(200, 163, 85, 0.2);

		backdrop-filter:
			blur(4px);

		margin-bottom: 12px;

		margin-right: 12px;

		opacity: 0.6; /* Transparência suave */

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


		/* Header */

		.header {

			padding: 0 8px;
		}



		.mobile-toggle {

			display: flex;
		}



		.brand {

			flex: 1;

			margin-left: 4px;

			gap: 8px;
		}



		.logo-img {

			height: 30px;
		}



		.game-title {

			font-size: 1rem;
		}



		.version-tag {

			font-size: 0.65rem;
		}



		.header-actions {

			gap: 6px;
		}



		.language-selector {

			font-size: 0.7rem;

			padding: 4px 4px;
		}



		.checklist-status {

			display: none;
		}



		/* Editor não aparece no mobile */

		.editor-ui,
		.editor-status {

			display: none !important;
		}



		/* Sidebar Desktop desaparece no telemóvel */

		.desktop-sidebar {

			display: none;
		}



		/* O mapa ocupa 100% do ecrã */

		.map-wrapper {

			left: 0;

			width: 100%;
		}



		/* Popup ligeiramente menor em mobile */

		:global(.deepmap-popup) {

			width: 275px;
		}



		:global(.deepmap-popup-image-wrapper) {

			height: 145px;
		}



		/* ==========================================
		   MENU MOBILE INDEPENDENTE
		   ========================================== */

		.mobile-menu-layer {

			display: none;

			position: fixed;

			top: 56px;

			left: 0;

			right: 0;

			bottom: 0;

			z-index: 20000;

			pointer-events: none;
		}



		/* Quando o checkbox está activo, mostra o menu */

		.mobile-menu-checkbox:checked ~ .mobile-menu-layer {

			display: block;

			pointer-events: auto;
		}



		/* Troca ☰ por X */

		.mobile-menu-checkbox:checked ~ .header .mobile-toggle .menu-icon {

			display: none;
		}



		.mobile-menu-checkbox:checked ~ .header .mobile-toggle .close-icon {

			display: block;
		}



		.mobile-backdrop {

			display: block;

			position: absolute;

			top: 0;

			left: 0;

			right: 0;

			bottom: 0;

			background:
				rgba(0, 0, 0, 0.65);
		}



		.mobile-sidebar {

			display: block;

			position: absolute;

			top: 0;

			left: 0;

			bottom: 0;

			width:
				min(300px, 85vw);

			background: #16161a;

			border-right:
				1px solid #2a2a30;

			box-shadow:
				8px 0 30px
					rgba(0, 0, 0, 0.6);

			box-sizing: border-box;

			z-index: 1;

			overflow-y: auto;
		}



		.mobile-sidebar-header {

			height: 56px;

			display: flex;

			align-items: center;

			justify-content:
				space-between;

			padding:
				0 12px 0 20px;

			border-bottom:
				1px solid #2a2a30;

			box-sizing:
				border-box;
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

			touch-action:
				manipulation;
		}



		.mobile-sidebar .sidebar-content {

			height: auto;

			padding: 20px;
		}
	}

</style>