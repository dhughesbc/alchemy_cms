module Alchemy
  module Admin
    class ElementsController < Alchemy::Admin::BaseController
      before_action :load_element, only: [:update, :trash, :fold, :publish]
      authorize_resource class: Alchemy::Element

      def index
        @page = Page.find(params[:page_id])
        @elements = @page.unfixed_elements
        @fixed_elements = @page.fixed_elements
      end

      def list
        @page_id = params[:page_id]
        if @page_id.blank? && !params[:page_urlname].blank?
          @page_id = Language.current.pages.find_by(urlname: params[:page_urlname]).id
        end
        @elements = Element.published.where(page_id: @page_id)
      end

      def new
        @page = Page.find(params[:page_id])
        @parent_element = Element.find_by(id: params[:parent_element_id])
        @elements = @page.available_element_definitions(
          @parent_element.try(:name),
          params[:fixed_only].present?
        )
        @element = @page.elements.build
        @clipboard = get_clipboard('elements')
        @clipboard_items = Element.all_from_clipboard_for_page(@clipboard, @page)
      end

      # Creates a element as discribed in config/alchemy/elements.yml on page via AJAX.
      def create
        @page = Page.find(params[:element][:page_id])
        Element.transaction do
          @element = element_from_clipboard_or_create
          if params['insert_at'] == 'top'
            @element.move_to_top
          end
        end
        if @element.valid?
          render :create
        else
          @element.page = @page
          @elements = @page.available_element_definitions
          @clipboard = get_clipboard('elements')
          @clipboard_items = Element.all_from_clipboard_for_page(@clipboard, @page)
          render :new
        end
      end

      # Updates the element.
      #
      # And update all contents in the elements by calling update_contents.
      #
      def update
        if @element.update_contents(contents_params)
          @page = @element.page
          @element_validated = @element.update_attributes!(element_params)
        else
          @element_validated = false
          @notice = _t('Validation failed')
          @error_message = "<h2>#{@notice}</h2><p>#{_t(:content_validations_headline)}</p>".html_safe
        end
      end

      def publish
        @element.update(public: !@element.public?)
      end

      # Trashes the Element instead of deleting it.
      def trash
        @page = @element.page
        @element.trash!
      end

      def order
        @trashed_element_ids = Element.trashed.where(id: params[:element_ids]).pluck(:id)
        Element.transaction do
          params[:element_ids].each_with_index do |element_id, idx|
            # Ensure to set page_id, cell_id and parent_element_id to the current page and
            # cell because of trashed elements could still have old values
            Element.where(id: element_id).update_all(
              page_id: params[:page_id],
              cell_id: params[:cell_id],
              parent_element_id: params[:parent_element_id],
              position: idx + 1
            )
          end
        end
      end

      def fold
        @page = @element.page
        @element.folded = !@element.folded
        @element.save
      end

      private

      def load_element
        @element = Element.find(params[:id])
      end

      def element_from_clipboard_or_create
        if params[:paste_from_clipboard].present?
          paste_element_from_clipboard
        else
          Element.create_from_scratch(params[:element])
        end
      end

      def element_from_clipboard
        @element_from_clipboard ||= begin
          @clipboard = get_clipboard('elements')
          @clipboard.detect { |item| item['id'].to_i == params[:paste_from_clipboard].to_i }
        end
      end

      def paste_element_from_clipboard
        @source_element = Element.find(element_from_clipboard['id'])
        new_attributes = {:page_id => @page.id}
        if @page.can_have_fixed_elements?
          new_attributes = new_attributes.merge({:cell_id => find_or_create_cell.try(:id)})
        end
        element = Element.copy(@source_element, new_attributes)
        if element_from_clipboard['action'] == 'cut'
          cut_element
        end
        element
      end

      def cut_element
        @cutted_element_id = @source_element.id
        @clipboard.delete_if { |item| item['id'] == @source_element.id.to_s }
        @source_element.destroy
      end

      def contents_params
        params.fetch(:contents, {}).permit!
      end

      def element_params
        if @element.taggable?
          params.fetch(:element, {}).permit(:tag_list)
        else
          params.fetch(:element, {})
        end
      end
    end
  end
end
