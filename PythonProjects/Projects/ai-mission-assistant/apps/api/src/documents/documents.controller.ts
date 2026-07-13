import {
  Controller,
  Post,
  Get,
  Delete,
  Param,
  UseGuards,
  Request,
  UseInterceptors,
  UploadedFile,
  ParseFilePipe,
  MaxFileSizeValidator,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiTags, ApiBearerAuth, ApiConsumes, ApiBody, ApiOperation } from '@nestjs/swagger';
import { diskStorage } from 'multer';
import { extname } from 'path';
import { v4 as uuidv4 } from 'uuid';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { DocumentsService } from './documents.service';

@ApiTags('documents')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('documents')
export class DocumentsController {
  constructor(private documentsService: DocumentsService) {}

  @Post('upload')
  @ApiOperation({ summary: 'Upload a PDF document' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: { file: { type: 'string', format: 'binary' } },
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: './storage/uploads',
        filename: (_req, file, cb) => {
          const uniqueName = `${uuidv4()}${extname(file.originalname)}`;
          cb(null, uniqueName);
        },
      }),
    }),
  )
  upload(
    @UploadedFile(
      new ParseFilePipe({
        validators: [
          new MaxFileSizeValidator({ maxSize: 20 * 1024 * 1024 }), // 20MB
        ],
      }),
    )
    file: Express.Multer.File,
    @Request() req: { user: { id: string } },
  ) {
    return this.documentsService.upload(req.user.id, file);
  }

  @Get()
  @ApiOperation({ summary: 'List all documents for the current user' })
  findAll(@Request() req: { user: { id: string } }) {
    return this.documentsService.findAll(req.user.id);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a single document' })
  findOne(@Param('id') id: string, @Request() req: { user: { id: string } }) {
    return this.documentsService.findOne(id, req.user.id);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete a document and its chunks' })
  remove(@Param('id') id: string, @Request() req: { user: { id: string } }) {
    return this.documentsService.remove(id, req.user.id);
  }
}
