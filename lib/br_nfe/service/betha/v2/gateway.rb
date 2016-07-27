module BrNfe
	module Service
		module Betha
			module V2
				class Gateway < BrNfe::Service::Betha::Base
					
					attr_accessor :numero_nfse
					attr_accessor :codigo_cancelamento

					def namespaces
						{"xmlns:e" => "http://www.betha.com.br/e-nota-contribuinte-ws"}
					end

					def namespace_identifier
						:e
					end

					def version
						:v2
					end

					def wsdl
						"http://e-gov.betha.com.br/e-nota-contribuinte-#{'test-' if env == :test}ws/nfseWS?wsdl"
					end

					def request
						set_response( client_wsdl.call(method_wsdl, message: "#{cabecalho}#{content_xml}") )
					rescue Savon::SOAPFault => error
						return @response = BrNfe::Service::Response::Default.new(success: false, error_messages: [error.message])
					end

					def builder
						@builder
					end

					def cabecalho
						Nokogiri::XML::Builder.new do
							nfseCabecMsg do
								cdata(Nokogiri::XML::Builder.new do |xml|
									xml.cabecalho(xmlns: "http://www.betha.com.br/e-nota-contribuinte-ws", versao: "2.02"){
										xml.versaoDados 2.02
									}
								end.doc.root)
							end
						end.doc.root.to_s.gsub(/\n/,'').gsub(/\t/,'')
					end

					def content_xml
						Nokogiri::XML::Builder.new do	
							nfseDadosMsg do
								cdata(canonical_xml_builder)
							end
						end.doc.root.to_s
					end

					def canonical_xml_builder
						canonicalize xml_builder.doc.root
					end
					
				private

					def format_data_xml_for_signature(data_xml)
						xml = Nokogiri::XML(data_xml.to_s, &:noblanks)
						node_name = xml.root.node_name
						xml = xml.root.xpath("//#{node_name}")
						xml.attr("xmlns", "http://www.betha.com.br/e-nota-contribuinte-ws")
						canonicalize xml.to_s
					end

					def xml_intermediario_servico(intermediario)
						return Nokogiri::XML::Builder.new unless intermediario
						Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
							xml.Intermediario{
								xml.IdentificacaoIntermediario{
									xml.CpfCnpj{
										tag_cpf_cnpj(xml, intermediario.cpf_cnpj)
									}
									xml.InscricaoMunicipal "#{intermediario.inscricao_municipal}".max_size(15) unless intermediario.inscricao_municipal.blank?
								}
								xml.RazaoSocial "#{intermediario.razao_social}".max_size(150)
							}
						end
					end

					def xml_prestador
						Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
							xml.Prestador{ 
								xml.CpfCnpj{
									tag_cpf_cnpj(xml, emitente.cnpj)
								}
								xml.InscricaoMunicipal "#{emitente.inscricao_municipal}".max_size(15) if !emitente.inscricao_municipal.blank? && env == :production
							}
						end
					end

					def xml_dados_servico(rps)
						Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
							xml.Servico {
								xml.Valores {
									xml.ValorServicos          value_monetary(rps.total_services,          2)                   
									xml.ValorDeducoes          value_monetary(rps.deductions,              2) unless rps.deductions.blank?
									xml.ValorPis               value_monetary(rps.valor_pis,               2) unless rps.valor_pis.blank?
									xml.ValorCofins            value_monetary(rps.valor_cofins,            2) unless rps.valor_cofins.blank?
									xml.ValorInss              value_monetary(rps.valor_inss,              2) unless rps.valor_inss.blank?
									xml.ValorIr                value_monetary(rps.valor_ir,                2) unless rps.valor_ir.blank?
									xml.ValorCsll              value_monetary(rps.valor_csll,              2) unless rps.valor_csll.blank?
									xml.OutrasRetencoes        value_monetary(rps.outras_retencoes,        2) unless rps.outras_retencoes.blank?
									xml.ValorIss               value_monetary(rps.total_iss,               2) unless rps.total_iss.blank?
									xml.Aliquota               value_monetary(rps.iss_tax_rate,            2) unless rps.iss_tax_rate.blank?
									xml.DescontoIncondicionado value_monetary(rps.desconto_incondicionado, 2) unless rps.desconto_incondicionado.blank?
									xml.DescontoCondicionado   value_monetary(rps.desconto_condicionado,   2) unless rps.desconto_condicionado.blank?
								}

								xml.IssRetido                 value_true_false(rps.iss_retained?)
								xml.ResponsavelRetencao       "#{rps.responsavel_retencao}".max_size(1) unless rps.responsavel_retencao.blank?
								xml.ItemListaServico          BrNfe::Helper.only_number(rps.item_lista_servico).rjust(4,'0').max_size(5) unless rps.item_lista_servico.blank?
								
								# Não devo enviar o CNAE na base de testes pois o municipio enviado será 0 (zero)
								if env != :test
									xml.CodigoCnae                BrNfe::Helper.only_number(rps.cnae_code).max_size(7) unless rps.cnae_code.blank?
								end
								
								xml.CodigoTributacaoMunicipio "#{rps.codigo_tributacao_municipio}".max_size(20)      unless rps.codigo_tributacao_municipio.blank?
								xml.Discriminacao             "#{rps.description}".max_size(2_000).remove_accents
								
								# Na base de testes devo enviar o código do município como 0 (zero)
								xml.CodigoMunicipio           (env == :test ? 0 : BrNfe::Helper.only_number(rps.codigo_municipio).max_size(7))
								
								# Não posso enviar o CodigoPais se a exigibilidade_iss não for 4 (exportação) - by bethagambis.com
								xml.CodigoPais                BrNfe::Helper.only_number(rps.codigo_pais).max_size(4) if !rps.codigo_pais.blank? && rps.exigibilidade_iss == '4'
								
								xml.ExigibilidadeISS          "#{rps.exigibilidade_iss}".max_size(2)
								xml.MunicipioIncidencia       BrNfe::Helper.only_number(rps.municipio_incidencia).max_size(7) unless rps.municipio_incidencia.blank?
								xml.NumeroProcesso            rps.numero_processo.max_size(30)     unless rps.numero_processo.blank?
							}
						end
					end

					def xml_inf_declaracao_prestacao_servico(rps)
						Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
							xml.InfDeclaracaoPrestacaoServico('Id' => "rps#{rps.numero}") {
								xml.Rps { 
									# Identificação RPS
									xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( xml_identificacao_rps(rps).doc.root.to_s )

									xml.DataEmissao value_date(rps.data_emissao)
									xml.Status      "#{rps.status}".max_size(1)

									# RPS subistituido
									xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( xml_rps_substituido(rps).doc.root.to_s )
								} 

								# Dia, mês e ano da prestação do serviço
								# Quando houver RPS, a nota será gerada com base na <DataEmissao> do RPS, caso contrário utilizará a <Competencia>
								xml.Competencia value_date(rps.competencia)

								# Dados do(s) serviço(s)
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( xml_dados_servico(rps).doc.root.to_s )

								# Pestador / Emitente
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( xml_prestador.doc.root.to_s )

								# Tomador / Destinatário
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( xml_dados_tomador(rps.destinatario).doc.root.to_s )

								# Intermediario
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( xml_intermediario_servico(rps.intermediario).doc.root.to_s )
								
								# Dados Construção Civil
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( xml_dados_construcao_civil(rps).doc.root.to_s )

								# Código de identificação do regime especial de tributação: (1)Microempresa municipal, (2)Estimativa, (3)Sociedade de profissionais, (4)Cooperativa, (5)Microempresário Individual (MEI), (6)Microempresário e Empresa de Pequeno Porte (ME EPP) , 
								xml.RegimeEspecialTributacao "#{emitente.regime_especial_tributacao}".max_size(2) unless emitente.regime_especial_tributacao.blank?
								
								xml.OptanteSimplesNacional   value_true_false(emitente.optante_simples_nacional?) # (1)sim ----- (2)não
								xml.IncentivoFiscal          value_true_false(emitente.incentivo_fiscal?)         # (1)sim ----- (2)não
								
							}
						end
					end

					def xml_rps_assinado(rps)
						Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
							xml.Rps{
								arps = xml_inf_declaracao_prestacao_servico(rps).doc.root
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( arps.to_s )
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( assinatura_xml( arps.to_s, "#rps#{rps.numero}" ) )
							}
						end
					end

					def xml_pedido_cancelamento_assinado
						xml = Nokogiri::XML::Builder.new do |xml|
							xml.Pedido {
								inf_pedido_cancelamento = xml_inf_pedido_cancelamento.doc.root

								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( inf_pedido_cancelamento.to_s )
								xml.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( assinatura_xml(inf_pedido_cancelamento.to_s, "#nf#{numero_nfse}") )
							}							
						end						
					end

					def xml_inf_pedido_cancelamento
						Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
							xml.InfPedidoCancelamento(Id: "nf#{numero_nfse}"){
								xml.IdentificacaoNfse{
									xml.Numero BrNfe::Helper.only_number(numero_nfse).max_size(15)
									xml.CpfCnpj{
										tag_cpf_cnpj(xml, emitente.cnpj)
									}
									xml.InscricaoMunicipal emitente.inscricao_municipal.max_size(15) if !emitente.inscricao_municipal.blank? && env == :production
									xml.CodigoMunicipio    "#{emitente.endereco.codigo_municipio}".max_size(7)
								}
								xml.CodigoCancelamento "#{codigo_cancelamento}".max_size(4)
							}
						end
					end

				end
			end
		end
	end
end