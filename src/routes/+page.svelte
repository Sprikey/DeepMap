<script>
	import { onMount } from 'svelte';

	let mapContainer;
	let map;

	// =================================================
	// ESTADO DO EDITOR DE COORDENADAS
	// =================================================
	// Estas variáveis controlam apenas a ferramenta de
	// edição. Mais tarde isto pode evoluir para o painel
	// de administração do DeepMap.
	let editorMode = false;
	let editorMarker = null;
	let editorCoords = null;
	let copyStatus = '';

	onMount(async () => {
		const L = await import('leaflet');
		await import('leaflet/dist/leaflet.css');

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
				const div = L.DomUtil.create('div', 'map-watermark');

				div.innerHTML = `
					<img src="/logo.png" alt="DeepMap Logo" />
				`;

				return div;
			}
		});

		map.addControl(new LogoWatermark());

		// =================================================
		// CLIQUE DO EDITOR DE COORDENADAS
		// =================================================
		// O Leaflet trabalha com coordenadas [Y, X].
		// Como o nosso mapa usa CRS.Simple, o ponto clicado
		// corresponde directamente à posição na imagem.
		map.on('click', (e) => {
			// Se o editor estiver desligado, o clique
			// funciona normalmente e não fazemos nada.
			if (!editorMode) return;

			const x = Math.round(e.latlng.lng);
			const y = Math.round(e.latlng.lat);

			editorCoords = {
				x,
				y
			};

			// Se já existir um marcador temporário,
			// removemo-lo antes de criar o novo.
			if (editorMarker) {
				map.removeLayer(editorMarker);
			}

			// Usamos um círculo em vez do marcador normal
			// do Leaflet para evitar dependências de ícones.
			editorMarker = L.circleMarker([y, x], {
				radius: 8,
				color: '#c8a355',
				fillColor: '#c8a355',
				fillOpacity: 0.8,
				weight: 2
			}).addTo(map);

			copyStatus = '';
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

	// =================================================
	// LIGAR / DESLIGAR O EDITOR
	// =================================================
	function toggleEditor() {
		editorMode = !editorMode;
		copyStatus = '';

		// Ao desligar o editor, removemos o marcador
		// temporário para deixar o mapa completamente limpo.
		if (!editorMode) {
			if (editorMarker && map) {
				map.removeLayer(editorMarker);
				editorMarker = null;
			}

			editorCoords = null;
		}
	}

	// =================================================
	// COPIAR COORDENADAS
	// =================================================
	async function copyCoordinates() {
		if (!editorCoords) return;

		const coordinates = `[${editorCoords.y}, ${editorCoords.x}]`;

		try {
			await navigator.clipboard.writeText(coordinates);
			copyStatus = 'COPIADO!';
		} catch (error) {
			// Fallback para ambientes onde o Clipboard API
			// não esteja disponível.
			const textArea = document.createElement('textarea');

			textArea.value = coordinates;
			textArea.style.position = 'fixed';
			textArea.style.opacity = '0';

			document.body.appendChild(textArea);
			textArea.select();

			try {
				document.execCommand('copy');
				copyStatus = 'COPIADO!';
			} catch (copyError) {
				copyStatus = 'ERRO';
			}

			document.body.removeChild(textArea);
		}

		// Depois de alguns segundos removemos a mensagem.
		setTimeout(() => {
			copyStatus = '';
		}, 2000);
	}
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
			<img src="/logo.png" alt="DeepMap" class="logo-img" />

			<span class="game-title">
				Elden Ring
			</span>

			<span class="version-tag">
				v1.0.21
			</span>
		</div>

		<div class="checklist-status">
			Checklist <span>(0%)</span>
		</div>

	</header>

	<!-- ================================================= -->
	<!-- FERRAMENTA DE COORDENADAS -->
	<!-- Apenas aparece no PC -->
	<!-- ================================================= -->

	<div class="coordinate-editor">

		<button
			class:active={editorMode}
			class="editor-toggle"
			onclick={toggleEditor}
		>
			⚙️ {editorMode ? 'EDITOR ON' : 'EDITOR'}
		</button>

		{#if editorMode && editorCoords}

			<div class="coordinate-panel">

				<div class="coordinate-title">
					COORDENADAS
				</div>

				<div class="coordinate-values">

					<div>
						<span>X</span>
						<strong>{editorCoords.x}</strong>
					</div>

					<div>
						<span>Y</span>
						<strong>{editorCoords.y}</strong>
					</div>

				</div>

				<div class="coordinate-array">
					[{editorCoords.y}, {editorCoords.x}]
				</div>

				<button
					class="copy-button"
					onclick={copyCoordinates}
				>
					{copyStatus || 'COPIAR'}
				</button>

			</div>

		{/if}

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
			<div bind:this={mapContainer} class="map-element"></div>
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

				<h2>Filtros</h2>

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
		font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
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
	   EDITOR DE COORDENADAS
	   Apenas visível no PC.
	   ========================================== */

	.coordinate-editor {
		position: fixed;
		top: 68px;
		right: 16px;

		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 8px;

		z-index: 11000;
	}

	.editor-toggle {
		padding: 8px 12px;

		background: #16161a;
		color: #c8a355;

		border: 1px solid #333340;
		border-radius: 6px;

		font-size: 0.8rem;
		font-weight: 700;

		cursor: pointer;

		box-shadow: 0 4px 12px rgba(0, 0, 0, 0.35);
	}

	.editor-toggle:hover {
		border-color: #c8a355;
	}

	.editor-toggle.active {
		background: #c8a355;
		color: #16161a;
		border-color: #c8a355;
	}

	.coordinate-panel {
		width: 190px;

		padding: 14px;

		background: rgba(22, 22, 26, 0.96);
		border: 1px solid #333340;
		border-radius: 8px;

		box-shadow: 0 8px 25px rgba(0, 0, 0, 0.5);

		box-sizing: border-box;
	}

	.coordinate-title {
		color: #c8a355;
		font-size: 0.75rem;
		font-weight: 700;
		letter-spacing: 1px;

		margin-bottom: 10px;
	}

	.coordinate-values {
		display: flex;
		gap: 20px;
		margin-bottom: 10px;
	}

	.coordinate-values div {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.coordinate-values span {
		color: #888;
		font-size: 0.7rem;
		text-transform: uppercase;
	}

	.coordinate-values strong {
		color: #e0e0e0;
		font-size: 1rem;
	}

	.coordinate-array {
		padding: 8px;

		background: #0b0b0e;
		border: 1px solid #2a2a30;
		border-radius: 4px;

		color: #e0e0e0;

		font-family: monospace;
		font-size: 0.85rem;

		text-align: center;

		margin-bottom: 10px;
	}

	.copy-button {
		width: 100%;

		padding: 8px;

		background: #22222a;
		color: #c8a355;

		border: 1px solid #333340;
		border-radius: 4px;

		font-size: 0.75rem;
		font-weight: 700;

		cursor: pointer;
	}

	.copy-button:hover {
		background: #2a2a30;
		border-color: #c8a355;
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
		   EDITOR DE COORDENADAS
		   Escondido no telemóvel por enquanto.
		   ========================================== */

		.coordinate-editor {
			display: none;
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

			box-shadow: 8px 0 30px rgba(0, 0, 0, 0.6);

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