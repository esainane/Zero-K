local menu_athena = { -- TODO_RENAME_FILE
	items = {
	  {
		angle = -90,
		unit = "cloakcon",
		label = "Bots",
		items = {
		  {
			angle= -45,
			unit = "spiderscout",
		  },
		  { 
			angle = -135,
			unit = "corak",
		  },
		  { 
			angle = -180,
			unit = "spherepole",
		  },
		  { 
			angle = 0,
			unit = "cloakaa",
		  },
		  { 
			angle = 45,
			unit = "cloakassault",
		  },
		}
	  },
	{
		angle = 0,
		unit = "spiderskirm",
		label = "Walkers",
		items = {
		  { 
			angle = -90,
			unit = "cloaksnipe",
		  },
		  { 
			angle = 135,
			unit = "spherecloaker",
		  },
		  { 
			angle = -135,
			unit = "shieldshield",
		  },	
		  {
			angle = -45,
			unit = "spiderantiheavy"
		  },
		  { 
			angle = 90,
			unit = "amphtele",
		  },		  
		  {
			angle = 45,
			unit = "slowmort"
		  },
		}
	  },
	  {
		angle = 90,
		unit = "staticradar",
		label = "Support",
		items = {
		  {
			angle = 45,
			unit = "staticheavyradar"
		  },
		  {
			angle = 135,
			unit = "staticjammer"
		  },		  
		  {
			angle = 180,
			unit = "staticcon"
		  },		  
		}
	  },
	  {
		angle = 180,
		unit = "panther",
		label = "Misc.",
		items = {
		  {
			angle = 90,
			unit = "vehheavyarty"
		  },
		  {
			angle = 135,
			unit = "striderantiheavy"
		  },		  
		  {
			angle = -90,
			unit = "hoverassault"
		  },		  
		}
	  },	  
  }
}

return menu_athena

