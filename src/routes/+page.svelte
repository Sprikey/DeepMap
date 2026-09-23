<script>
	import { onMount } from 'svelte';

	let mapContainer;
	let map;

	/* ==========================================
	   EDITOR DE COORDENADAS
	   ========================================== */

	let Leaflet;
	let editorMode = false;
	let editorMarker = null;

	let editorX = null;
	let editorY = null;

	/*
		Atualiza visualmente toda a interface do editor.

		A interface fica sempre presente no HTML.
		Não depende de {#if}, para evitar o problema
		que tivemos nas versões anteriores.
	*/
	function updateEditorInterface() {
		if (typeof document === 'undefined') return;

		const editorButton = document.getElementById('editor-toggle');
		const editorStatus = document.getElementById('editor-status');
		const coordinatePanel = document.getElementById('coordinate-panel');

		const xValue = document.getElementById('editor-x');
		const yValue = document.getElementById('editor-y');
		const arrayValue = document.getElementById('editor-array');

		const instruction = document.getElementById('editor-instruction');
		const coordinatesContent = document.getElementById('coordinates-content');

		const copyButton = document.getElementById('copy-coordinates');
		const copyStatus = document.getElementById('copy-status');

		/* Editor desligado */
		if (!editorMode) {

			if (editorButton) {
				editorButton.textContent = '⚙️ EDITOR';
				editorButton.classList.remove('active');
			}

			if (editorStatus) {
				editorStatus.style.display = 'none';
			}

			if (coordinatePanel) {
				coordinatePanel.style.display = 'none';
			}

			return;
		}

		/* Editor ligado */

		if (editorButton) {
			editorButton.textContent = '🛠️ EDITOR ATIVO';
			editorButton.classList.add('active');
		}

		if (editorStatus) {
			editorStatus.style.display = 'flex';
		}

		if (coordinatePanel) {
			coordinatePanel.style.display = 'block';
		}

		/* Ainda não foi selecionado nenhum ponto */

		if (editorX === null || editorY === null) {

			if (instruction) {
				instruction.style.display = 'block';
			}

			if (coordinatesContent) {
				coordinatesContent.style.display = 'none';
			}

			if (copyButton) {
				copyButton.disabled = true;
			}

			if (copyStatus) {
				copyStatus.textContent = '';
			}

			return;
		}

		/* Já temos coordenadas */

		if (instruction) {
			instruction.style.display = 'none';
		}

		if (coordinatesContent) {
			coordinatesContent.style.display = 'block';
		}

		if (xValue) {
			xValue.textContent = editorX;
		}

		if (yValue) {
			yValue.textContent = editorY;
		}

		/*
			Leaflet utiliza:

			[Y, X]

			Ou seja:
			[latitude, longitude]
		*/
		if (arrayValue) {
			arrayValue.textContent = `[${editorY}, ${editorX}]`;
		}

		if (copyButton) {
			copyButton.disabled = false;
		}

		if (copyStatus) {
			copyStatus.textContent = '';
		}
	}

	/* Liga / desliga o modo editor */
	function toggleEditor() {

		editorMode = !editorMode;

		/* Ao desligar o editor removemos o marcador temporário */
		if (!editorMode) {

			if (editorMarker && map) {
				map.removeLayer(editorMarker);
			}

			editorMarker = null;

			editorX = null;
			editorY = null;
		}

		updateEditorInterface();
	}

	/* Copiar coordenadas diretamente no formato Leaflet */
	async function copyCoordinates() {

		if (editorX === null || editorY === null) return;

		const coordinates = `[${editorY}, ${editorX}]`;

		const copyStatus = document.getElementById('copy-status');

		try {

			await navigator.clipboard.writeText(coordinates);

			if (copyStatus) {
				copyStatus.textContent = '✓ Copiado!';
			}

		} catch (error) {

			/*
				Fallback para browsers onde
				navigator.clipboard não esteja disponível
			*/

			const textarea = document.createElement('textarea');

			textarea.value = coordinates;
			textarea.style.position = 'fixed';
			textarea.style.opacity = '0';

			document.body.appendChild(textarea);

			textarea.select();

			document.execCommand('copy');

			document.body.removeChild(textarea);

			if (copyStatus) {
				copyStatus.textContent = '✓ Copiado!';
			}
		}
	}

	onMount(async () => {

		const L = await import('leaflet');
		await import('leaflet/dist/leaflet.css');

		/* Guardamos o Leaflet para usar no editor */
		Leaflet = L;

		const height = 8000;
		const width = 8000;

		const bounds = [
			[0, 0],
			[height, width]
		];

		map = L.map(mapContainer, {
			crs: L.CRS.Simple,
			maxBounds: bounds,
			maxBoundsViscosity: 0.8,
			attributionControl: false,
			minZoom: -3,
			maxZoom: 2,
			zoomSnap: 0.25
		});

		const imageOverlay = L.imageOverlay(
			'/mapa-elden-ring.jpg',
			bounds
		).addTo(map);

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
					<img src="/logo.png" alt="DeepMap Logo" />
				`;

				return div;
			}
		});

		map.addControl(new LogoWatermark());

		/* ==========================================
		   CLIQUE NO MAPA — EDITOR
		   ========================================== */

		map.on('click', (e) => {

			/* Se o editor estiver desligado não fazemos nada */
			if (!editorMode) return;

			/*
				Leaflet devolve:

				lat = Y
				lng = X
			*/

			const x = Math.round(e.latlng.lng);
			const y = Math.round(e.latlng.lat);

			editorX = x;
			editorY = y;

			/*
				Remove o círculo anterior para existir
				apenas um marcador temporário.
			*/

			if (editorMarker) {
				map.removeLayer(editorMarker);
			}

			/*
				Marcador temporário do ponto selecionado
			*/

			editorMarker = Leaflet.circleMarker(
				[y, x],
				{
					radius: 9,
					color: '#ff9f1c',
					weight: 3,
					fillColor: '#ff9f1c',
					fillOpacity: 0.45
				}
			).addTo(map);

			/* Atualiza a janela das coordenadas */
			updateEditorInterface();
		});

		imageOverlay.on('load', () => {
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

	<!-- ================================================= -->
	<!-- CONTROLO DO MENU MOBILE -->
	<!-- Checkbox invisível: o CSS controla abrir/fechar -->
	<!-- ================================================= -->

	<input
		type="checkbox"
		id="mobile-menu-toggle"
		class="mobile-menu-checkbox"
	/>

	<!-- Header Superior -->
	<header class="header">

		<!-- Botão do menu apenas para mobile -->
		<label
			for="mobile-menu-toggle"
			class="mobile-toggle"
			aria-label="Abrir Menu"
		>
			<span class="menu-icon">☰</span>
			<span class="close-icon">✕</span>
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
				v1.0.23
			</span>

		</div>

		<div class="checklist-status">
			Checklist <span>(0%)</span>
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
			⚙️ EDITOR
		</button>


		<!-- Janela do editor -->
		<div
			id="coordinate-panel"
			class="coordinate-panel"
		>

			<div class="coordinate-title">
				🛠️ EDITOR DE COORDENADAS
			</div>


			<!-- Aparece antes de clicar no mapa -->
			<div
				id="editor-instruction"
				class="editor-instruction"
			>
				Clica num ponto do mapa para obter as coordenadas.
			</div>


			<!-- Aparece depois de clicar no mapa -->
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


				<div class="coordinate-divider"></div>


				<div class="coordinate-label">
					Pronto para Leaflet:
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
					📋 COPIAR
				</button>


				<div
					id="copy-status"
					class="copy-status"
				></div>

			</div>

		</div>

	</div>


	<!-- Barra que confirma que o editor está ligado -->
	<div
		id="editor-status"
		class="editor-status"
	>
		<span class="editor-status-dot"></span>

		MODO EDITOR ATIVO — Clica no mapa
	</div>


	<!-- Conteúdo principal -->
	<div class="body-container">

		<!-- Sidebar Desktop -->
		<aside class="desktop-sidebar">

			<div class="sidebar-content">

				<h2>Filtros</h2>

				<div class="filter-group">

					<h3>Locais</h3>

					<label>
						<input type="checkbox" checked />
						Sites of Grace
					</label>

					<label>
						<input type="checkbox" checked />
						Dungeons & Cavernas
					</label>

					<label>
						<input type="checkbox" checked />
						Bosses
					</label>

				</div>

				<div class="filter-group">

					<h3>Colecionáveis</h3>

					<label>
						<input type="checkbox" checked />
						Armas e Equipamentos
					</label>

					<label>
						<input type="checkbox" checked />
						Stonesword Keys
					</label>

					<label>
						<input type="checkbox" checked />
						Talismãs
					</label>

				</div>

			</div>

		</aside>


		<!-- Contentor do Mapa Leaflet -->
		<main class="map-wrapper">

			<div
				bind:this={mapContainer}
				class="map-element"
			></div>

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
			aria-label="Fechar Menu"
		></label>


		<aside class="mobile-sidebar">

			<div class="mobile-sidebar-header">

				<h2>
					Filtros
				</h2>

				<label
					for="mobile-menu-toggle"
					class="mobile-close"
					aria-label="Fechar Menu"
				>
					✕
				</label>

			</div>


			<div class="sidebar-content">

				<div class="filter-group">

					<h3>Locais</h3>

					<label>
						<input type="checkbox" checked />
						Sites of Grace
					</label>

					<label>
						<input type="checkbox" checked />
						Dungeons & Cavernas
					</label>

					<label>
						<input type="checkbox" checked />
						Bosses
					</label>

				</div>


				<div class="filter-group">

					<h3>Colecionáveis</h3>

					<label>
						<input type="checkbox" checked />
						Armas e Equipamentos
					</label>

					<label>
						<input type="checkbox" checked />
						Stonesword Keys
					</label>

					<label>
						<input type="checkbox" checked />
						Talismãs
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

		border-bottom: 1px solid #2a2a30;

		display: flex;

		align-items: center;

		justify-content: space-between;

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

		border: 1px solid #333340;
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

		border: 1px solid #c8a355;

		border-radius: 6px;

		color: #c8a355;

		font-size: 0.78rem;

		font-weight: 700;

		letter-spacing: 0.5px;

		cursor: pointer;

		box-shadow: 0 4px 15px rgba(0, 0, 0, 0.4);

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
			0 0 0 2px rgba(200, 163, 85, 0.15),
			0 5px 20px rgba(0, 0, 0, 0.5);
	}


	.coordinate-panel {

		display: none;

		margin-top: 10px;

		background: rgba(22, 22, 26, 0.97);

		border: 1px solid #c8a355;

		border-radius: 8px;

		padding: 16px;

		box-sizing: border-box;

		box-shadow:
			0 8px 30px rgba(0, 0, 0, 0.65);

		backdrop-filter: blur(8px);

		pointer-events: auto;
	}


	.coordinate-title {

		color: #c8a355;

		font-size: 0.8rem;

		font-weight: 700;

		letter-spacing: 0.6px;

		margin-bottom: 14px;

		padding-bottom: 10px;

		border-bottom: 1px solid #2a2a30;
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

		justify-content: space-between;

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

		text-transform: uppercase;

		letter-spacing: 0.5px;

		margin-bottom: 7px;
	}


	.coordinate-array {

		background: #0b0b0e;

		border: 1px solid #333340;

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

		transition:
			opacity 0.2s,
			transform 0.1s;
	}


	.copy-button:hover:not(:disabled) {
		opacity: 0.9;
	}


	.copy-button:active:not(:disabled) {
		transform: scale(0.98);
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


	/*
		Indicador independente no topo.

		Serve para sabermos imediatamente
		que o modo editor está realmente ativo.
	*/

	.editor-status {

		display: none;

		position: fixed !important;

		top: 68px !important;

		left: 50% !important;

		transform: translateX(-50%);

		align-items: center;

		gap: 8px;

		padding: 8px 14px;

		background: rgba(22, 22, 26, 0.96);

		border: 1px solid #ff9f1c;

		border-radius: 6px;

		color: #ffb340;

		font-size: 0.76rem;

		font-weight: 800;

		letter-spacing: 0.4px;

		box-shadow:
			0 5px 20px rgba(0, 0, 0, 0.55);

		z-index: 999999 !important;

		pointer-events: none;
	}


	.editor-status-dot {

		width: 8px;

		height: 8px;

		border-radius: 50%;

		background: #ff9f1c;

		box-shadow:
			0 0 8px rgba(255, 159, 28, 0.8);
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


	/* Marca d'água no canto inferior direito (Apenas logo e bem transparente) */

	:global(.map-watermark) {

		display: flex;

		align-items: center;

		justify-content: center;

		background: rgba(22, 22, 26, 0.5);

		padding: 6px;

		border-radius: 8px;

		border: 1px solid rgba(200, 163, 85, 0.2);

		backdrop-filter: blur(4px);

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


		.checklist-status {
			display: none;
		}


		/* ==========================================
		   EDITOR NÃO APARECE NO MOBILE
		   ========================================== */

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

</style>