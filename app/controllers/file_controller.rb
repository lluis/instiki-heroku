# Controller responsible for serving files and pictures.

require 'zip/zip'

class FileController < ApplicationController

  layout 'default'
  
  before_filter :check_allow_uploads

  def file
    @file_name = params['id']
    if @params['file']
      # form supplied
      new_file = @web.wiki_files.create(@params['file'])
      if new_file.valid?
        flash[:info] = "File '#{@file_name}' successfully uploaded"
        return_to_last_remembered
      else
        # pass the file with errors back into the form
        @file = new_file
        render
      end
    else
      # no form supplied, this is a request to download the file
      file = WikiFile.find_by_file_name(@file_name)
      if file 
        send_data(file.content, determine_file_options_for(@file_name, :filename => @file_name))
      else
        @file = WikiFile.new(:file_name => @file_name)
        render
      end
    end
  end

  def cancel_upload
    return_to_last_remembered
  end
  
  def import
    if @params['file']
      @problems = []
      import_file_name = "#{@web.address}-import-#{Time.now.strftime('%Y-%m-%d-%H-%M-%S')}.zip"
      import_from_archive(@params['file'].path)
      if @problems.empty?
        flash[:info] = 'Import successfully finished'
      else
        flash[:error] = 'Import finished, but some pages were not imported:<li>' + 
            @problems.join('</li><li>') + '</li>'
      end
      return_to_last_remembered
    else
      # to template
    end
  end

  protected

  def check_allow_uploads
    render(:status => 404, :text => "Web #{@params['web'].inspect} not found") and return false unless @web
    if @web.allow_uploads?
      return true
    else
      render :status => 403, :text => 'File uploads are blocked by the webmaster' 
      return false
    end
  end
  
  private 
  
  def import_from_archive(archive)
    logger.info "Importing pages from #{archive}"
    zip = Zip::ZipInputStream.open(archive)
    while (entry = zip.get_next_entry) do
      ext_length = File.extname(entry.name).length
      page_name = entry.name[0..-(ext_length + 1)]
      page_content = entry.get_input_stream.read
      logger.info "Processing page '#{page_name}'"
      begin
        existing_page = @wiki.read_page(@web.address, page_name)
        if existing_page
          if existing_page.content == page_content
            logger.info "Page '#{page_name}' with the same content already exists. Skipping."
            next
          else
            logger.info "Page '#{page_name}' already exists. Adding a new revision to it."
            wiki.revise_page(@web.address, page_name, page_content, Time.now, @author, PageRenderer.new)
          end
        else
          wiki.write_page(@web.address, page_name, page_content, Time.now, @author, PageRenderer.new)
        end
      rescue => e
        logger.error(e)
        @problems << "#{page_name} : #{e.message}"
      end
    end
    logger.info "Import from #{archive} finished"
  end

end