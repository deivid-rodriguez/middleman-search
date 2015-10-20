module Middleman
  module Sitemap
    class SearchIndexResource < ::Middleman::Sitemap::Resource
      def initialize(store, path, options)
        @resources_to_index = options[:resources]
        @fields = options[:fields]
        super(store, path)
      end

      def template?
        false
      end

      def get_source_file
        path
      end

      def render
        # Build js context
        context = V8::Context.new
        context.load(File.expand_path('../../../vendor/assets/javascripts/lunr.min.js', __FILE__))
        context.eval('lunr.Index.prototype.indexJson = function () {return JSON.stringify(this);}')

        # Build lunr based on config
        lunr = context.eval('lunr')
        lunr_conf = proc do |this|
          this.ref('id')
          @fields.each do |field, opts|
            next if opts[:index] == false
            this.field(field, {:boost => opts[:boost]})
          end
        end

        # Get lunr index
        index = lunr.call(lunr_conf)

        # Ref to resource map
        store = Hash.new

        # Iterate over all resources and build index
        @app.sitemap.resources.each_with_index do |resource, id|
          catch(:required) do
            next if resource.data['index'] == false
            next unless @resources_to_index.any? {|whitelisted| resource.path.start_with? whitelisted }

            to_index = Hash.new
            to_store = Hash.new

            @fields.each do |field, opts|
              value = value_for(resource, field, opts)
              throw(:required) if value.blank? && opts[:required]
              to_index[field] = value unless opts[:index] == false
              to_store[field] = value if opts[:store]
            end

            index.add(to_index.merge(id: id))
            store[id] = to_store
          end
        end

        # Generate JSON output
        "{\"index\": #{index.indexJson()}, \"docs\": #{store.to_json}}"
      end

      def binary?
        false
      end

      def ignored?
        false
      end

      def value_for(resource, field, opts={})
        case field.to_s
        when 'content'
          Nokogiri::HTML(resource.render(layout: false)).xpath("//text()").text
        when 'url'
          resource.url
        else
          value = resource.data.send(field) || resource.metadata.fetch(:options, {}).fetch(:data, {}).fetch(field, nil)
          value ? Array(value).compact.join(" ") : nil
        end
      end
    end
  end
end
