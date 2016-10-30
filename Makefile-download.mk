# http://www.nationalatlas.gov/atlasftp-1m.html
gz/%.tar.gz:
	mkdir -p $(dir $@)
	curl 'http://dds.cr.usgs.gov/pub/data/nationalatlas/$(notdir $@)' -o $@.download
	mv $@.download $@

# New England towns (ie, sub-counties)
gz/tl_2015_%_cousub.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/COUSUB/$(notdir $@)' -o $@.download
	mv $@.download $@

# Zip Code Tabulation Areas
gz/tl_2015_us_zcta510.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/ZCTA5/$(notdir $@)' -o $@.download
	mv $@.download $@

# Census Tracts
gz/tl_2015_%_tract.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/TRACT/$(notdir $@)' -o $@.download
	mv $@.download $@

# Census Block Groups
gz/tl_2015_%_bg.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/BG/$(notdir $@)' -o $@.download
	mv $@.download $@

# Census Blocks
gz/tl_2015_%_tabblock.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/TABBLOCK/$(notdir $@)' -o $@.download
	mv $@.download $@

gz/tabblock2010_%_pophu.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2010BLKPOPHU/$(notdir $@)' -o $@.download
	mv $@.download $@

# Core Based Statistical Areas
gz/tl_2015_us_cbsa.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/CBSA/$(notdir $@)' -o $@.download
	mv $@.download $@

# Congressional Districts (Alternative)
gz/tl_2015_us_cd114.zip:
	mkdir -p $(dir $@)
	curl 'ftp://ftp2.census.gov/geo/tiger/TIGER2015/CD/$(notdir $@)' -o $@.download
	mv $@.download $@

# State legislative districts upper
gz/tl_2015_%_sldu.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/SLDU/$(notdir $@)' -o $@.download
	mv $@.download $@

# State legislative districts lower
gz/tl_2015_%_sldl.zip:
	mkdir -p $(dir $@)
	curl 'http://www2.census.gov/geo/tiger/TIGER2015/SLDL/$(notdir $@)' -o $@.download
	mv $@.download $@

