<script>
	import { onMount } from 'svelte';

	let mapContainer;
	let map;
	let sidebarAberta = false;

	function toggleSidebar() {
		sidebarAberta = !sidebarAberta;
		setTimeout(() => {
			if (map) map.invalidateSize();
		}, 300);
	}

	onMount(async () => {
		const L = await import('leaflet');
		import('leaflet/dist/leaflet.css');

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

		// Carrega a imagem do mapa (.jpg)
		const imageOverlay = L.imageOverlay('/mapa-elden-ring.jpg', bounds).addTo(map);

		// Marca d'água no canto inferior direito do mapa
		const LogoWatermark = L.Control.extend({
			options: { position: 'bottomright' },
			onAdd: function () {
				const div = L.DomUtil.create('div', 'map-watermark');
				div.innerHTML = `<img src="/logo.png" alt="DeepMap Logo" /> <span>DeepMap</span>`;
				return div;
			}
		});
		map.addControl(new LogoWatermark());

		imageOverlay.on('load', () => {
			map.fitBounds(bounds);
		});

		map.fitBounds(bounds);
		
		setTimeout(() => {
			if (map) map.invalidateSize();
		}, 250);
	});
</script>

<div class="app-container">
	<!-- Header Superior -->
	<header class="header">
		<button class="mobile-toggle" on:click={toggleSidebar} aria-label="Abrir Menu">
			{sidebarAberta ? '✕' : '☰'}
		</button>

		<div class="brand">
			<img src="/logo.png" alt="DeepMap" class="logo-img" />
			<div class="brand-text">
				<span class="brand-title">DeepMap</span>
				<span class="brand-separator">|</span>
				<span class="game-title">Elden Ring</span>
			</div>
		</div>

		<div class="checklist-status">
			Checklist <span>(0%)</span>
		</div>
	</header>

	<div class="body-container">
		{#if sidebarAberta}
			<div class="backdrop" on:click={toggleSidebar} role="presentation"></div>
		{/if}

		<!-- Barra Lateral -->
		<aside class="sidebar" class:open={sidebarAberta}>
			<div class="sidebar-content">
				<h2>Filtros</h2>
				
				<div class="filter-group">
					<h3>Locais</h3>
					<label><input type="checkbox" checked /> Sites of Grace</label>
					<label><input type="checkbox" checked /> Dungeons & Cavernas</label>
					<label><input type="checkbox" checked /> Bosses</label>
				</div>

				<div class="filter-group">
					<h3>Colecionáveis</h3>
					<label><input type="checkbox" checked /> Armas e Equipamentos</label>
					<label><input type="checkbox" checked /> Stonesword Keys</label>
					<label><input type="checkbox" checked /> Talismãs</label>
				</div>
			</div>
		</aside>

		<!-- Contentor do Mapa Leaflet -->
		<main class="map-wrapper">
			<div bind:this={mapContainer} class="map-element"></div>
		</main>
	</div>
</div>

<style>
	:global(body, html) {
		margin: 0;
		padding: 0;
		height: 100%;
		width: 100%;
		overflow: hidden;
		background-color: #0b0b0e;
		font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
		color: #e0e0e0;
	}

	.app-container {
		display: flex;
		flex-direction: column;
		height: 100vh;
		width: 100vw;
	}

	/* Header */
	.header {
		height: 56px;
		background: #16161a;
		border-bottom: 1px solid #2a2a30;
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 16px;
		z-index: 1001;
	}

	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.logo-img {
		height: 32px;
		width: auto;
	}

	.brand-text {
		display: flex;
		align-items: center;
		gap: 8px;
	}

	.brand-title {
		font-size: 1.2rem;
		font-weight: 700;
		color: #c8a355;
		letter-spacing: 0.5px;
	}

	.brand-separator {
		color: #4a4a55;
		font-weight: 300;
		font-size: 1.1rem;
	}

	.game-title {
		font-size: 1rem;
		font-weight: 500;
		color: #a0a0ab;
		letter-spacing: 0.5px;
	}

	.checklist-status {
		font-size: 0.9rem;
		color: #a0a0a0;
	}

	.checklist-status span {
		color: #c8a355;
		font-weight: 600;
	}

	.mobile-toggle {
		display: none;
		background: transparent;
		border: none;
		color: #c8a355;
		font-size: 1.5rem;
		cursor: pointer;
		padding: 4px;
	}

	/* Body & Sidebar */
	.body-container {
		display: flex;
		flex: 1;
		position: relative;
		overflow: hidden;
	}

	.sidebar {
		width: 300px;
		background: #16161a;
		border-right: 1px solid #2a2a30;
		display: flex;
		flex-direction: column;
		transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
		z-index: 1000;
	}

	.sidebar-content {
		padding: 20px;
		overflow-y: auto;
	}

	.sidebar h2 {
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

	/* Mapa */
	.map-wrapper {
		flex: 1;
		height: 100%;
		width: 100%;
		position: relative;
		background: #0b0b0e;
	}

	.map-element {
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		right: 0;
		background: #0b0b0e;
	}

	/* Marca d'água no canto inferior direito */
	:global(.map-watermark) {
		display: flex;
		align-items: center;
		gap: 8px;
		background: rgba(22, 22, 26, 0.85);
		padding: 6px 12px;
		border-radius: 6px;
		border: 1px solid rgba(200, 163, 85, 0.3);
		backdrop-filter: blur(4px);
		margin-bottom: 12px;
		margin-right: 12px;
		pointer-events: none;
	}

	:global(.map-watermark img) {
		height: 22px;
		width: auto;
	}

	:global(.map-watermark span) {
		color: #c8a355;
		font-weight: 600;
		font-size: 0.85rem;
		letter-spacing: 0.5px;
	}

	/* Media Query para Mobile */
	@media (max-width: 768px) {
		.mobile-toggle {
			display: block;
		}

		.game-title {
			display: none; /* Em ecrãs muito pequenos esconde o texto "Elden Ring" para não apertar a barra */
		}

		.brand-separator {
			display: none;
		}

		.sidebar {
			position: absolute;
			top: 0;
			bottom: 0;
			left: 0;
			width: 280px;
			transform: translateX(-100%);
			box-shadow: 4px 0 12px rgba(0, 0, 0, 0.5);
		}

		.sidebar.open {
			transform: translateX(0);
		}

		.backdrop {
			position: absolute;
			inset: 0;
			background: rgba(0, 0, 0, 0.6);
			backdrop-filter: blur(2px);
			z-index: 999;
		}
	}
</style>