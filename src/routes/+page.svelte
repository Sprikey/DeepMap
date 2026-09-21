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

		const bounds = [
			[0, 0],
			[8000, 8000]
		];

		map = L.map(mapContainer, {
			crs: L.CRS.Simple,
			maxBounds: bounds,
			maxBoundsViscosity: 1.0,
			attributionControl: false,
			minZoom: -2,
			maxZoom: 2
		});

		L.imageOverlay('/mapa-elden-ring.png', bounds).addTo(map);
		map.fitBounds(bounds);

		// Garantir ajuste correto em telemóvel
		setTimeout(() => {
			map.invalidateSize();
		}, 200);
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
			<span class="brand-title">Elden Ring</span>
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

		<!-- Mapa Leaflet -->
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
		background-color: #0d0d0f;
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

	.brand-title {
		font-size: 1.25rem;
		font-weight: 700;
		color: #c8a355;
		letter-spacing: 1px;
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
		background: #0d0d0f;
	}

	.map-element {
		height: 100%;
		width: 100%;
		background: #0d0d0f;
	}

	/* Media Query para Mobile */
	@media (max-width: 768px) {
		.mobile-toggle {
			display: block;
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