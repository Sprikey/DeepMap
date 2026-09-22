<script>
	import { onMount } from 'svelte';

	let mapContainer;
	let map;
	let sidebarAberta = false;
 

	function toggleSidebar() {
	console.log('BOTAO CLICADO');
	sidebarAberta = !sidebarAberta;
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

		// Apenas a imagem do logo no canto inferior direito, mais transparente
		const LogoWatermark = L.Control.extend({
			options: { position: 'bottomright' },
			onAdd: function () {
				const div = L.DomUtil.create('div', 'map-watermark');
				div.innerHTML = `<img src="/logo.png" alt="DeepMap Logo" />`;
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

 <button
	type="button"
	class="mobile-toggle"
	aria-label={sidebarAberta ? 'Fechar Menu' : 'Abrir Menu'}
	onclick={toggleSidebar}
>
	{sidebarAberta ? '✕' : '☰'}
</button>

		<div class="brand">
			<img src="/logo.png" alt="DeepMap" class="logo-img" />
			<span class="game-title">Elden Ring</span>
      <!-- Adiciona esta linha temporária: -->
      <span class="version-tag">v1.0.6</span>
		</div>

		<div class="checklist-status">
			Checklist <span>(0%)</span>
		</div>
	</header>

	<div class="body-container">
		{#if sidebarAberta}
			<div class="backdrop" onclick={toggleSidebar} role="presentation"></div>
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
    position: fixed; /* ADICIONAR ESTA LINHA para travar o scroll da página no telemóvel */
		background-color: #0b0b0e;
		font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
		color: #e0e0e0;
	}

	.app-container {
	display: flex;
	flex-direction: column;
	height: 100vh;
	height: 100dvh; /* ADICIONAR ESTA LINHA: 100dvh ajusta à altura exata nos navegadores mobile */
	width: 100vw;
	overflow: hidden;
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
  z-index: 9999; /* Valor muito elevado para garantir prioridade total */
  position: fixed; /* Posicionamento fixo sobre a janela */
  top: 0;
  left: 0;
  right: 0;
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

	.mobile-toggle {
  display: none;
  background: transparent;
  border: none;
  color: #c8a355;
  font-size: 1.8rem;
  cursor: pointer;
  padding: 8px 12px;
  position: relative;
  z-index: 100000;
  -webkit-tap-highlight-color: transparent;
  touch-action: manipulation;
  pointer-events: auto;
}


	/* Body & Sidebar */
	.body-container {
		display: flex;
		flex: 1;
		position: relative;
		overflow: hidden;
    margin-top: 56px; /* Compensa a altura do header fixo */
    height: calc(100vh - 56px);
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

	/* Media Query para Mobile */
	@media (max-width: 768px) {
  .mobile-toggle {
    display: block !important;
    position: relative;
    z-index: 100000;
    flex-shrink: 0;
  }

  .sidebar {
    position: fixed;
    top: 56px;
    bottom: 0;
    left: 0;
    width: 280px;
    transform: translateX(-100%);
    box-shadow: 4px 0 12px rgba(0, 0, 0, 0.5);
    z-index: 9998;
  }

  .sidebar.open {
    transform: translateX(0);
  }

  .backdrop {
    position: fixed;
    inset: 56px 0 0 0;
    background: rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(2px);
    z-index: 9997;
  }
}
</style>