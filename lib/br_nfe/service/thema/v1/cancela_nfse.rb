module BrNfe
	module Service
		module Thema
			module V1
				class CancelaNfse < BrNfe::Service::Thema::V1::Base
					include BrNfe::Service::Concerns::Rules::CancelamentoNfs

					def method_wsdl
						:cancelar_nfse
					end

					def response_path_module
						BrNfe::Service::Response::Paths::V1::ServicoCancelarNfseResposta
					end

					def xml_builder
						render_xml 'servico_cancelar_nfse_envio'
					end

					# Não é utilizado o response_root_path pois
					# esse órgão emissor trata o XML de forma diferente
					# e para instanciar a resposta adequadamente é utilizado o 
					# body_xml_path.
					# A resposta contém outro XML dentro do Body.
					#
					def response_root_path
						[]
					end

					# Caminho de hash através do body da resposta SOAP até encontrar
					# o XML correspondente na qual contém as informações necessárias 
					# para encontrar os valores para setar na resposta
					#
					def body_xml_path
						[:cancelar_nfse_response, :return]
					end

					# Tag root da requisição
					#
					def soap_body_root_tag
						'cancelarNfse'
					end

				end
			end
		end
	end
end