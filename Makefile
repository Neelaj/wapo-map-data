# add node_modules/.bin to path for turf-cli
export PATH := node_modules/.bin:$(PATH)

.SECONDARY:

include Makefile-shp.mk

# National
geojson/states.geojson: shp/us/states.shp
	mkdir -p $(dir $@)
	rm -f $@
	ogr2ogr -f "GeoJSON" $(dir $@)states-temp.json $< \
		-dialect sqlite -sql \
		"select ST_union(Geometry),STATE_FIPS from states GROUP BY STATE_FIPS"
	cat $(dir $@)states-temp.json | ./clip-at-dateline > $@
	rm $(dir $@)states-temp.json

geojson/counties.geojson: shp/us/counties.shp
	mkdir -p $(dir $@)
	rm -f $@
	ogr2ogr -f "GeoJSON" $(dir $@)counties-temp.json $< \
		-dialect sqlite -sql \
		"select ST_union(Geometry),STATE_FIPS,FIPS from counties GROUP BY STATE_FIPS,FIPS"
	cat $(dir $@)counties-temp.json | ./clip-at-dateline > $@
	rm $(dir $@)counties-temp.json

geojson/districts.geojson: shp/us/congress-clipped.shp
	mkdir -p $(dir $@)
	rm -rf $@
	ogr2ogr -f "GeoJSON" $(dir $@)districts-temp.json $< \
		-dialect sqlite -sql \
		"select ST_union(Geometry),GEOID,STATEFP from 'congress-clipped' GROUP BY GEOID"
	cat $(dir $@)districts-temp.json | ./clip-at-dateline | ./normalize-district > $@
	rm $(dir $@)districts-temp.json

geojson/precincts:
	aws s3 sync s3://wapo-precincts/geojson $@

geojson/precincts.ndjson: geojson/precincts
	cat geojson/precincts/DC.geojson \
		| sed 's/Precinct/precinct/g' \
		| jq '.features[] | .properties.id = .id | del(.id)' \
		> $(dir $@)precincts.ndjson
	cat geojson/precincts/NC_pctgeo.js \
		| jq '.features[] | .properties.id = .properties.reportingu | del(.properties.reportingu)' \
		>> $(dir $@)precincts.ndjson

geojson/precincts.geojson: geojson/precincts.ndjson
	cat $^ | jq -s '{type: "FeatureCollection", features: .}' > $@

# Simplified copies certain geojson targets
geojson/us-10m: geojson/counties.geojson geojson/districts.geojson geojson/states.geojson geojson/precincts.geojson
	mkdir -p $@
	node_modules/.bin/topojson \
		-o $(dir $@)temp.json \
		--no-pre-quantization \
		--post-quantization=1e6 \
		--simplify=7e-7 \
		--properties id,GEOID,STATE_FIPS,FIPS\
		--external-properties data/fips.csv \
		-- $^
	node_modules/.bin/topojson-geojson -o $@ $(dir $@)temp.json
	for f in $$(ls $@) ; do mv $@/$$f $@/$$(basename $$f .json).geojson; done
	rm $(dir $@)temp.json

geojson/us-lowzoom/%: geojson/%
	mkdir -p geojson/us-lowzoom
	node_modules/.bin/topojson \
		-o $(dir $@)temp.json \
		--no-pre-quantization \
		--post-quantization=1e6 \
		--simplify=3e-6 \
		--properties id,GEOID,STATE_FIPS,FIPS\
		--external-properties data/fips.csv \
		-- $^
	node_modules/.bin/topojson-geojson -o geojson/us-lowzoom geojson/us-lowzoom/temp.json
	rm geojson/us-lowzoom/temp.json

geojson/us-smallest/%: geojson/%
	mkdir -p geojson/us-smallest
	node_modules/.bin/topojson \
		-o $(dir $@)temp.json \
		--no-pre-quantization \
		--post-quantization=1e6 \
		--simplify=3e-5 \
		--properties id,GEOID,STATE_FIPS,FIPS\
		--external-properties data/fips.csv \
		-- $^
	node_modules/.bin/topojson-geojson -o geojson/us-smallest geojson/us-smallest/temp.json
	rm geojson/us-smallest/temp.json

geojson/us-lowzoom-factory: 
	make geojson/us-lowzoom/states.geojson
	make geojson/us-lowzoom/counties.geojson
	make geojson/us-lowzoom/districts.geojson

geojson/us-smallest-factory:
	make geojson/us-smallest/states.geojson
	make geojson/us-smallest/counties.geojson
	make geojson/us-smallest/districts.geojson

#
# Albers
#
geojson/albers/%.geojson: geojson/%.geojson
	mkdir -p $(dir $@)
	cat $^ \
		| ./reproject-geojson \
		| ./normalize-properties id:id GEOID:id STATE_FIPS:id FIPS:id  \
		| ./add-geojson-id id \
		> $@

geojson/albers/us-10m: geojson/us-10m
	make geojson/albers/us-10m/states.geojson
	make geojson/albers/us-10m/counties.geojson
	make geojson/albers/us-10m/districts.geojson
	make geojson/albers/us-10m/precincts.geojson

geojson/albers/us-lowzoom: geojson/us-lowzoom
	make geojson/albers/us-lowzoom/states.geojson
	make geojson/albers/us-lowzoom/counties.geojson
	make geojson/albers/us-lowzoom/districts.geojson

geojson/albers/us-smallest: geojson/us-smallest
	make geojson/albers/us-smallest/states.geojson
	make geojson/albers/us-smallest/counties.geojson
	make geojson/albers/us-smallest/districts.geojson

geojson/albers/relative-area.csv: geojson/albers/us-10m
	$(eval TOTAL_AREA = \
		$(shell cat geojson/albers/us-10m/states.geojson \
			| ./reproject-geojson --projection mercator --reverse \
			| ./sum-area))
	echo "id,area" > $@
	cat geojson/albers/us-10m/states.geojson \
		| ./reproject-geojson --projection mercator --reverse \
		| ./calculate-area --normalize $(TOTAL_AREA) --precision 6 >> $@
	cat geojson/albers/us-10m/counties.geojson \
		| ./reproject-geojson --projection mercator --reverse \
		| ./calculate-area --normalize $(TOTAL_AREA) --precision 6 >> $@
	cat geojson/albers/us-10m/districts.geojson \
		| ./reproject-geojson --projection mercator --reverse \
		| ./calculate-area --normalize $(TOTAL_AREA) --precision 6 >> $@
	cat geojson/albers/us-10m/precincts.geojson \
		| ./reproject-geojson --projection mercator --reverse \
		| ./calculate-area --normalize $(TOTAL_AREA) --precision 8 >> $@

# Separate asset needed by wapo-components
geojson/albers/state-bounds.json: geojson/albers/states.geojson
	cat $^ | ./extract-projected-bounds > $@

# Separate asset needed by wapo-components
geojson/albers/tile-index.json: geojson/albers/us-10m
	cat $^/states.geojson geojson/cartogram/boundaries.geojson \
		| ./reproject-geojson --projection mercator --reverse \
		| node_modules/.bin/tile-index -z 5 -f indexed > $@

geojson/albers/centroid-%: geojson/albers/%
	cat $^ \
		| ./reproject-geojson --projection mercator --reverse \
		| ./centroids \
		| ./reproject-geojson --projection mercator > $@

# Separate asset needed by wapo-components
geojson/albers/centroid-radius-data.json: geojson/albers/centroid-states.geojson \
	geojson/albers/centroid-districts.geojson \
	geojson/albers/centroid-counties.geojson
	cat $^ \
		| jq '.features[].properties' | jq -s . \
		> $@

geojson/cartogram/%.geojson: data/cartogram/%.geojson
	mkdir -p $(dir $@)
	cat $^ \
		| ./invert-cartogram-coords \
		| ./reproject-geojson --projection mercator \
		> $@

geojson/cartogram:
	make geojson/cartogram/boundaries.geojson
	make geojson/cartogram/electoral-units.geojson

geojson/cartogram/cartogram-bounds.json: geojson/cartogram/boundaries.geojson
	cat $^ | ./extract-projected-bounds > $@

geojson/albers/state-labels-dataset.geojson:
	# Note: Need to preclude this with Mapbox Token
	curl "https://api.mapbox.com/datasets/v1/devseed/cis7wq7mj04l92zpk9tbk9wgo/features?access_token=$(MapboxAccessToken)" > $@

geojson/albers/state-labels.geojson: geojson/albers/state-labels-dataset.geojson
	# Note: reprojecting using 'mercator' because the incoming data was _already_ reprojected
	# to albers so it could be edited in the Mapbox Studio dataset editor
	cat $^ \
		| jq '{ type: "FeatureCollection", \
					  features: .features | \
							map(. | select(.geometry.type == "Point" and .properties.type != "callout")) \
					}' \
		| ./reproject-geojson --projection mercator \
		| node_modules/.bin/geojson-join \
			--format=csv --againstField=postal --geojsonField=postal data/fips.csv \
		| ./normalize-properties \
				statePostal:statePostal postal:statePostal \
				STATE_FIPS:id id:id \
				type:type \
		| ./add-geojson-id id \
		> $@

geojson/albers/state-label-callouts.geojson: geojson/albers/state-labels-dataset.geojson
	# Note: reprojecting using 'mercator' because the incoming data was _already_ reprojected
	# to albers so it could be edited in the Mapbox Studio dataset editor
	cat $^ \
		| jq '{ type: "FeatureCollection", \
					  features: .features | \
							map(. | select(.properties.type == "callout" or .geometry.type == "LineString")) \
					}' \
		| ./reproject-geojson --projection mercator \
		| node_modules/.bin/geojson-join \
			--format=csv --againstField=postal --geojsonField=postal data/fips.csv \
		| ./normalize-properties \
				statePostal:statePostal postal:statePostal \
				STATE_FIPS:id id:id \
				type:type \
		| ./add-geojson-id id \
		> $@

geojson/albers/city-labels.geojson:
	cat data/us-cities.geojson \
		| jq '{ type: "FeatureCollection", \
					  features: .features | \
							map(. | select(.geometry.type == "Point" and .properties.visible == 1)) \
					}' \
		| ./reproject-geojson \
		| ./capitalize-property name \
		| ./normalize-properties \
				adm1name:state state:state \
				visible:visible \
				national:national \
				align:align \
				name:name \
		> $@

tiles/merged.mbtiles: tiles/election.mbtiles \
	tiles/election-centroids.mbtiles \
	tiles/election-city-labels.mbtiles
	tile-join -fo $@ $^
	echo "Merged tiles built as $@.  Upload this file to s3://wapo-election-tiles/merged-vX.mbtiles, and then update wapo-components/build_scripts/build-screenshotter.sh to point to the new version."

tiles/election-centroids.mbtiles: geojson/albers/centroid-states.geojson \
	geojson/albers/centroid-counties.geojson \
	geojson/albers/centroid-districts.geojson \
	geojson/albers/centroid-precincts.geojson
	mkdir -p $(dir $@)
	tippecanoe --projection EPSG:3857 \
		-f \
		--named-layer=states-centroids:geojson/albers/centroid-states.geojson \
		--named-layer=counties-centroids:geojson/albers/centroid-counties.geojson \
		--named-layer=districts-centroids:geojson/albers/centroid-districts.geojson \
		--named-layer=precincts-centroids:geojson/albers/centroid-precincts.geojson \
		--read-parallel \
		--no-polygon-splitting \
		--drop-rate=0 \
		--name=2016-us-election-centroids \
		--output $@

tiles/election-cartogram.mbtiles: geojson/cartogram/electoral-units.geojson \
	geojson/cartogram/boundaries.geojson \
	data/cartogram-labels.geojson
	mkdir -p $(dir $@)
	tippecanoe --projection EPSG:3857 \
		-f \
		--named-layer=electoral:geojson/cartogram/electoral-units.geojson \
		--named-layer=cartoboundaries:geojson/cartogram/boundaries.geojson \
		--named-layer=cartolabels:data/cartogram-labels.geojson \
		--read-parallel \
		--no-polygon-splitting \
		--maximum-zoom=8 \
		--drop-rate=0 \
		--name=2016-us-election-cartogram \
		--output $@

tiles/election-city-labels.mbtiles: geojson/albers/city-labels.geojson
	mkdir -p $(dir $@)
	tippecanoe --projection EPSG:3857 \
		-f \
		--named-layer=city-labels:geojson/albers/city-labels.geojson \
		--read-parallel \
		--no-polygon-splitting \
		--drop-rate=0 \
		--name=2016-us-election-cities \
		--buffer=20 \
		--output $@

tiles/z0-1.mbtiles: geojson/albers/us-smallest/states.geojson \
	geojson/albers/us-smallest/counties.geojson \
	geojson/albers/us-smallest/districts.geojson \
	geojson/albers/state-labels.geojson \
	geojson/albers/state-label-callouts.geojson
	mkdir -p $(dir $@)
	tippecanoe --projection EPSG:3857 \
		-f \
		--named-layer=states:geojson/albers/us-smallest/states.geojson \
		--named-layer=counties:geojson/albers/us-smallest/counties.geojson \
		--named-layer=districts:geojson/albers/us-smallest/districts.geojson \
		--named-layer=precincts:geojson/albers/us-smallest/precincts.geojson \
		--named-layer=state-labels:geojson/albers/state-labels.geojson \
		--named-layer=state-label-callouts:geojson/albers/state-label-callouts.geojson \
		--read-parallel \
		--no-polygon-splitting \
		--maximum-zoom=1 \
		--drop-rate=0 \
		--name=2016-us-election \
		--output $@

tiles/z2-3.mbtiles: geojson/albers/us-lowzoom/states.geojson \
	geojson/albers/us-lowzoom/counties.geojson \
	geojson/albers/us-lowzoom/districts.geojson \
	geojson/albers/state-labels.geojson \
	geojson/albers/state-label-callouts.geojson
	mkdir -p $(dir $@)
	tippecanoe --projection EPSG:3857 \
		-f \
		--named-layer=states:geojson/albers/us-lowzoom/states.geojson \
		--named-layer=counties:geojson/albers/us-lowzoom/counties.geojson \
		--named-layer=districts:geojson/albers/us-lowzoom/districts.geojson \
		--named-layer=state-labels:geojson/albers/state-labels.geojson \
		--named-layer=state-label-callouts:geojson/albers/state-label-callouts.geojson \
		--read-parallel \
		--no-polygon-splitting \
		--minimum-zoom=2 \
		--maximum-zoom=3 \
		--drop-rate=0 \
		--name=2016-us-election \
		--output $@

tiles/z4-6.mbtiles: geojson/albers/us-10m \
	geojson/albers/state-labels.geojson \
	geojson/albers/state-label-callouts.geojson
	mkdir -p $(dir $@)
	tippecanoe --projection EPSG:3857 \
		-f \
		--named-layer=states:geojson/albers/us-10m/states.geojson \
		--named-layer=counties:geojson/albers/us-10m/counties.geojson \
		--named-layer=districts:geojson/albers/us-10m/districts.geojson \
		--named-layer=precincts:geojson/albers/us-10m/precincts.geojson \
		--named-layer=state-labels:geojson/albers/state-labels.geojson \
		--named-layer=state-label-callouts:geojson/albers/state-label-callouts.geojson \
		--read-parallel \
		--no-polygon-splitting \
		--minimum-zoom=4 \
		--maximum-zoom=6 \
		--drop-rate=0 \
		--name=2016-us-election \
		--output $@

tiles/z7-12.mbtiles: geojson/albers/states.geojson \
	geojson/albers/counties.geojson \
	geojson/albers/districts.geojson \
	geojson/albers/precincts.geojson \
	geojson/albers/state-labels.geojson \
	geojson/albers/state-label-callouts.geojson
	mkdir -p $(dir $@)
	tippecanoe --projection EPSG:3857 \
		-f \
		--named-layer=states:geojson/albers/states.geojson \
		--named-layer=counties:geojson/albers/counties.geojson \
		--named-layer=districts:geojson/albers/districts.geojson \
		--named-layer=precincts:geojson/albers/precincts.geojson \
		--named-layer=state-labels:geojson/albers/state-labels.geojson \
		--named-layer=state-label-callouts:geojson/albers/state-label-callouts.geojson \
		--read-parallel \
		--no-polygon-splitting \
		--minimum-zoom=7 \
		--maximum-zoom=12 \
		--drop-rate=0 \
		--name=2016-us-election \
		--output $@

tiles/election.mbtiles: geojson/albers/relative-area.csv tiles/z0-1.mbtiles tiles/z2-3.mbtiles tiles/z4-6.mbtiles tiles/z7-12.mbtiles
	tile-join -f -o $@ -c geojson/albers/relative-area.csv tiles/z0-1.mbtiles tiles/z2-3.mbtiles tiles/z4-6.mbtiles tiles/z7-12.mbtiles

# Usage:
# TILESET=accountname.tilesetname make upload/tiles-filename
.PHONY: upload/%
upload/%: tiles/%.mbtiles
ifndef MapboxAccessToken
	$(error MapboxAccessToken not defined)
endif
ifndef TILESET
	$(error TILESET not defined)
endif
	./upload $(TILESET) $^


#
# State legislative districts
# (We may need these for special case states)
#

# State legislative district upper
topo/us-%-sldu.json: shp/%/sldu.shp
	mkdir -p $(dir $@)
	node_modules/.bin/topojson \
		-o $@ \
		--no-pre-quantization \
		--post-quantization=1e6 \
		--simplify=3e-8 \
		--id-property=+GEOID \
		--properties NAMELSAD \
		-- $<

geojson/%/sldu.geojson: topo/us-%-sldu.json
	node_modules/.bin/topojson-geojson -o $(dir $@) \
		--properties NAMELSAD \
		$<
		cat $(dir $@)sldu.json | ./clip-at-dateline > $@
		rm $(dir $@)sldu.json

# State legislative district lower
topo/us-%-sldl.json: shp/%/sldl.shp
	mkdir -p $(dir $@)
	node_modules/.bin/topojson \
		-o $@ \
		--no-pre-quantization \
		--post-quantization=1e6 \
		--simplify=3e-8 \
		--id-property=+GEOID \
		--properties NAMELSAD \
		-- $<

geojson/%/sldl.geojson: topo/us-%-sldl.json
	node_modules/.bin/topojson-geojson -o $(dir $@) \
		--properties NAMELSAD \
		$<
		cat $(dir $@)sldl.json | ./clip-at-dateline > $@
		rm $(dir $@)sldl.json

#
# Census blocks
# (Used for population dot density)
#
STATES=al ak az ar ca co ct de dc fl ga hi id il in ia ks ky la me md ma mi mn ms mo mt ne nv nh nj nm ny nc nd oh ok or pa ri sc sd tn tx ut vt va wa wv wi wy
.PHONY: all-pop-blocks
-all-pop-blocks:
