/* ==========================================
   LOCAIS — ELDEN RING
   ==========================================

   Aqui ficam os dados dos locais do mapa.

   Mais tarde será muito fácil adicionar
   novos locais sem mexer no +page.svelte.
*/


export const locations = [

	{

		id:
			'church-of-elleh',


		/* Layer a que pertence este marcador */

		mapLayer:
			'surface',


		/* Categoria utilizada pelos filtros */

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


		/*
			Por enquanto o ícone continua aqui
			para não alterarmos o funcionamento.

			Depois vamos mudar para:
			pino CSS + símbolo da categoria.
		*/

		icon:
			'/games/elden-ring/icons/site-of-grace.png',


		/* Imagem do popup */

		image:
			'/games/elden-ring/locations/sites-of-grace/church-of-elleh.jpg',


		/* Campos opcionais */

		npcs:
			[],

		items:
			[],

		quests:
			[],

		notesKey:
			null,


		/* Preparado para premium */

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
	},

{
    id: 'gatefront',

    mapLayer: 'surface',

    categoryId: 'site_of_grace',

    nameKey: 'gatefront',

    descriptionKey: 'gatefront_description',

    categoryKey: 'site_of_grace',

    regionKey: 'limgrave',

    coordinates: [2534, 3257],

    image: '/games/elden-ring/locations/sites-of-grace/gatefront.webp',

    npcs: [],
    items: [],
    quests: [],

    notesKey: null,

    premium: {
        provider: 'supabase',

        sections: [
            'npcs',
            'items',
            'quests',
            'notes'
        ]
    }
}

];